import Foundation

/// The Scheduled screen's data on one day: the board and the names its rows show.
public struct ScheduledListing: Equatable, Sendable {
    public var board: ScheduledBoard
    public var accounts: [Account]
    public var categories: [TransactionCategory]
    public var payees: [Payee]

    public init(
        board: ScheduledBoard,
        accounts: [Account] = [],
        categories: [TransactionCategory] = [],
        payees: [Payee] = [],
    ) {
        self.board = board
        self.accounts = accounts
        self.categories = categories
        self.payees = payees
    }

    public func account(_ id: UUID?) -> Account? {
        id.flatMap { id in accounts.first { $0.id == id } }
    }

    public func category(_ id: UUID?) -> TransactionCategory? {
        id.flatMap { id in categories.first { $0.id == id } }
    }

    public func payee(_ id: UUID?) -> Payee? {
        id.flatMap { id in payees.first { $0.id == id } }
    }

    /// The item, wherever it is on the board.
    public func item(_ id: UUID) -> ScheduledItem? {
        (board.overdue + board.dueToday + board.upcoming).first { $0.item.id == id }?.item
            ?? board.completed.first { $0.id == id }
    }
}

/// Reads the Scheduled screens (#26).
@MainActor
public protocol LoadScheduledUseCase {
    func listing() throws -> ScheduledListing
    /// Today, as the screens and the form use it.
    func today() -> CalendarDay
    /// The device's time zone now: a new item is dated in it, and the form's date pickers work in it.
    func currentTimeZoneID() -> String
}

/// Adds, changes and deletes scheduled items, and pays or skips their occurrences (#26).
@MainActor
public protocol ManageScheduledUseCase {
    /// Saves `item`. A new item carries the zone it was made in, `currentTimeZoneID()`, and keeps it.
    func save(_ item: ScheduledItem) throws
    func delete(id: UUID) throws
    /// Pay now: records the occurrence on `occurrence`, dated today. `nil` when it was already settled.
    @discardableResult
    func payNow(itemID: UUID, occurrence: CalendarDay) throws -> Transaction?
    /// Skip: settles the occurrence and records nothing.
    func skip(itemID: UUID, occurrence: CalendarDay) throws
}

/// Records the automatic items' due occurrences, each once (#26). Called at launch, before the badge is read,
/// and again whenever the app becomes active, so a day change while it's open is caught too.
@MainActor
public protocol CatchUpScheduledUseCase {
    /// `atLaunch` also removes items whose account was deleted in an earlier session (D288.1).
    func catchUp(atLaunch: Bool) throws -> ScheduledCatchUp
}

/// What catch-up recorded, per item, that the catch-up hint hasn't reported yet (D338.6). It stays pending until the
/// Scheduled screen has shown it, across other screens and relaunches, and goes when that screen is left after
/// showing it. It holds item IDs and days only; the screens word them.
@MainActor
public protocol ScheduledCatchUpNoticeUseCase: AnyObject {
    /// Merges one catch-up's recordings, per item, into what's pending, which then counts as not yet shown.
    func add(_ result: ScheduledCatchUp)
    /// What's pending, in the order the items were first recorded.
    func pending() -> [ScheduledCatchUpGroup]
    /// The Scheduled screen showed the hint.
    func markShown()
    /// The Scheduled screen was left: forget what it showed. What it hasn't shown stays.
    func dismissIfShown()
    /// Forget what's pending, for a hint with nothing left to show (its items were deleted) or after a restore.
    func clear()
    /// How many times `clear()` ran this launch, so a list still showing a hint it already reported can tell that
    /// a restore forgot it.
    var clearCount: Int { get }
}

/// Where the pending catch-up notice is kept between launches: app settings, not the ledger, so no backup holds it.
@MainActor
public protocol ScheduledCatchUpNoticeStore: AnyObject {
    func notice() -> ScheduledCatchUpNotice?
    func setNotice(_ notice: ScheduledCatchUpNotice?)
}

/// A notice store for one run only: tests and previews.
@MainActor
public final class InMemoryScheduledCatchUpNoticeStore: ScheduledCatchUpNoticeStore {
    private var stored: ScheduledCatchUpNotice?

    public init(_ notice: ScheduledCatchUpNotice? = nil) {
        stored = notice
    }

    public func notice() -> ScheduledCatchUpNotice? {
        stored
    }

    public func setNotice(_ notice: ScheduledCatchUpNotice?) {
        stored = notice
    }
}

/// The notice the composition root makes once per launch, shared by every window, over `store`.
@MainActor
public final class ScheduledCatchUpNotices: ScheduledCatchUpNoticeUseCase {
    private let store: any ScheduledCatchUpNoticeStore
    public private(set) var clearCount = 0

    /// A notice the previous run showed went when the app quit on the Scheduled screen: it was seen.
    public init(store: any ScheduledCatchUpNoticeStore = InMemoryScheduledCatchUpNoticeStore()) {
        self.store = store
        if store.notice()?.shown == true {
            store.setNotice(nil)
        }
    }

    public func add(_ result: ScheduledCatchUp) {
        let recorded = result.recordedByItem
        guard !recorded.isEmpty else {
            return
        }
        let groups = ScheduledCatchUpGroup.merging(store.notice()?.groups ?? [], with: recorded)
        store.setNotice(ScheduledCatchUpNotice(groups: groups, shown: false))
    }

    public func pending() -> [ScheduledCatchUpGroup] {
        store.notice()?.groups ?? []
    }

    public func markShown() {
        guard var notice = store.notice(), !notice.groups.isEmpty, !notice.shown else {
            return
        }
        notice.shown = true
        store.setNotice(notice)
    }

    public func dismissIfShown() {
        if store.notice()?.shown == true {
            store.setNotice(nil)
        }
    }

    public func clear() {
        store.setNotice(nil)
        clearCount += 1
    }
}

// MARK: - Implementations

/// The default scheduled use cases over one repository. The App injects the clock and the zone; they're read on
/// every call, so a clock or time zone
/// change while the app runs is picked up: "today" is the device's current day (D21).
@MainActor
public struct DefaultScheduledUseCases: LoadScheduledUseCase, ManageScheduledUseCase, CatchUpScheduledUseCase {
    private let repository: any ScheduleRepository
    private let now: @MainActor () -> Date
    private let timeZone: @MainActor () -> TimeZone

    public init(
        repository: any ScheduleRepository,
        now: @escaping @MainActor () -> Date,
        timeZone: @escaping @MainActor () -> TimeZone,
    ) {
        self.repository = repository
        self.now = now
        self.timeZone = timeZone
    }

    public func today() -> CalendarDay {
        TransactionTiming.today(now(), timeZone: timeZone())
    }

    public func currentTimeZoneID() -> String {
        timeZone().identifier
    }

    public func listing() throws -> ScheduledListing {
        let ledger = try repository.scheduleLedger()
        return ScheduledListing(
            board: ScheduledBoard.make(ledger, today: today()),
            accounts: ledger.accountsVisible(),
            categories: ledger.categoriesVisible(),
            payees: ledger.payeesVisible(),
        )
    }

    public func save(_ item: ScheduledItem) throws {
        try repository.saveScheduledItem(item, today: today(), now: now())
    }

    public func delete(id: UUID) throws {
        try repository.deleteScheduledItem(id: id)
    }

    @discardableResult
    public func payNow(itemID: UUID, occurrence: CalendarDay) throws -> Transaction? {
        try repository.settleScheduledOccurrence(.pay(itemID: itemID, occurrence: occurrence, postedOn: today()))
    }

    public func skip(itemID: UUID, occurrence: CalendarDay) throws {
        _ = try repository.settleScheduledOccurrence(.skip(itemID: itemID, occurrence: occurrence))
    }

    public func catchUp(atLaunch: Bool) throws -> ScheduledCatchUp {
        try repository.catchUpScheduledItems(today: today(), pruningOrphans: atLaunch)
    }
}

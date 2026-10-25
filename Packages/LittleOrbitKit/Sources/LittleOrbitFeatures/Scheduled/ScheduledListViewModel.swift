import Foundation
import LittleOrbitDomain
import Observation

/// The platform the wording follows: iOS rows are links, so its hint says how to reach Pay and Skip; Mac menus
/// take an ellipsis on items that ask first (D334.1, D334.10).
public enum ScheduledPlatform: Sendable {
    case iOS
    case macOS

    public static var current: ScheduledPlatform {
        #if os(macOS)
            .macOS
        #else
            .iOS
        #endif
    }
}

/// A screen of the Scheduled stack that presents the form, the confirmations and the alerts while it's on top.
public enum ScheduledScreen: Hashable, Sendable {
    case list
    case item(UUID)
    case completed
}

/// A pending Skip or Delete. Skip is an alert; Delete is a confirmation dialog on iOS and an alert on the Mac.
public struct ScheduledConfirmation: Identifiable, Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case skip(itemID: UUID, occurrence: CalendarDay)
        case delete(itemID: UUID)
    }

    public let id = UUID()
    public let action: Action
    public let title: String
    public let message: String
    public let confirmTitle: String
    public let isDestructive: Bool

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.action == rhs.action
    }
}

/// The Scheduled screen of one item: what it records, when, and each occurrence that needs paying or skipping.
public struct ScheduledItemDetail: Equatable, Sendable {
    public let itemID: UUID
    public let title: String
    public let amount: String
    public let tone: AmountTone
    /// Label and value pairs: Account, Category, Payee, Repeat, Starts, End Date, Note.
    public let facts: [ScheduledFact]
    /// "Next: 1 Nov", the next date on the schedule from today even while older days are overdue (D369), or
    /// "Ended 5 Oct" when none follows (D334.13).
    public let next: String
    /// The overdue and due-today occurrences, each with its own Pay Now and Skip (S76).
    public let due: [ScheduledRow]
}

public struct ScheduledFact: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: String
    public var id: String { label }
}

/// The Scheduled list (#26 design: Overdue, Due today, Upcoming, then Completed). Each missed occurrence has its own
/// row with Pay Now and Skip (S76); Pay Now records today with the occurrence's own key, so paying it twice, or
/// from two windows, records it once. Neither is an Undo step yet, and neither shows a toast (D290). It depends only
/// on use-case protocols.
@MainActor
@Observable
public final class ScheduledListViewModel {
    public private(set) var listing = ScheduledListing(
        board: ScheduledBoard(today: CalendarDay(year: 1970, month: 1, day: 1))
    )
    public var alert: CategoryAlert?
    public var confirmation: ScheduledConfirmation?
    public var form: ScheduledFormViewModel?

    /// The Scheduled screens on screen, in the order they appeared: the last one presents (see `presenter`).
    public private(set) var visibleScreens: [ScheduledScreen] = []
    /// Whether a load has read the listing, so a hint is never judged against the placeholder board.
    @ObservationIgnored private var loaded = false
    /// What catch-up recorded that the catch-up hint hasn't reported yet, read at each load (D338.6).
    public private(set) var pendingCatchUp: [ScheduledCatchUpGroup] = []
    /// Whether this list's hint row has actually appeared on screen. Only that marks the hint shown, never a load.
    @ObservationIgnored private var catchUpHintAppearedHere = false
    /// This list left the Scheduled screens after its hint appeared: the notice is gone from app settings, but this
    /// list keeps showing it if it comes back. The Mac's detail column may report the list disappearing and
    /// appearing again while it stays on screen, and that mustn't take away a hint that's still in view.
    @ObservationIgnored private var keepsHintAfterLeaving = false
    public let platform: ScheduledPlatform

    @ObservationIgnored private let useCases: ScheduledScreenUseCases
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let changed: () -> Void

    public init(
        useCases: ScheduledScreenUseCases,
        locale: Locale = .current,
        platform: ScheduledPlatform = .current,
        changed: @escaping () -> Void = {},
    ) {
        self.useCases = useCases
        self.locale = locale
        self.platform = platform
        self.changed = changed
    }

    private var rows: ScheduledPresenter {
        ScheduledPresenter(listing: listing, locale: locale)
    }

    // MARK: Reading

    public func load() {
        do {
            listing = try useCases.load.listing()
            loaded = true
        } catch {
            alert = ScheduledText.loadFailed
        }
        let stored = useCases.notices.pending()
        if !stored.isEmpty || !keepsHintAfterLeaving {
            pendingCatchUp = stored
            keepsHintAfterLeaving = false
        }
        forgetCatchUpHintWithNothingToName()
    }

    /// While the list is on screen, a pending catch-up hint with nothing left to name (its items were deleted) is
    /// forgotten (D338.6).
    private func forgetCatchUpHintWithNothingToName() {
        guard loaded, visibleScreens.contains(.list), !pendingCatchUp.isEmpty, catchUpHint == nil else {
            return
        }
        useCases.notices.clear()
        pendingCatchUp = []
    }

    /// The hint row appeared on screen: only now does the hint count as shown (D338.6).
    public func catchUpHintAppeared() {
        guard loaded, catchUpHint != nil else {
            return
        }
        catchUpHintAppearedHere = true
        useCases.notices.markShown()
    }

    // MARK: Presenting

    /// The screen on top, which attaches the sheet, the confirmations and the alert. Only that one presents, so a
    /// pushed item or Completed screen shows them, and the list under it never presents them twice.
    public var presenter: ScheduledScreen {
        visibleScreens.last ?? .list
    }

    public func screenAppeared(_ screen: ScheduledScreen) {
        visibleScreens.removeAll { $0 == screen }
        visibleScreens.append(screen)
        if screen == .list {
            forgetCatchUpHintWithNothingToName()
        }
    }

    public func screenDisappeared(_ screen: ScheduledScreen) {
        visibleScreens.removeAll { $0 == screen }
        // Leaving the Scheduled screens, not pushing onto the list, ends a shown catch-up hint (D338.6). A push may
        // report the list's disappearance before the pushed screen's appearance, so this looks after both.
        guard screen == .list, visibleScreens.isEmpty else {
            return
        }
        Task { @MainActor [weak self] in
            await Task.yield()
            if let self, self.visibleScreens.isEmpty {
                self.leftScheduled()
            }
        }
    }

    /// The list left the Scheduled screens: a shown hint goes from app settings, so the next visit doesn't show it,
    /// but one that appeared in this list stays in this list in case it was only re-shown in place (D338.6).
    private func leftScheduled() {
        useCases.notices.dismissIfShown()
        if catchUpHintAppearedHere && !pendingCatchUp.isEmpty {
            keepsHintAfterLeaving = true
        } else {
            pendingCatchUp = useCases.notices.pending()
        }
    }

    /// The Scheduled screens were left: a catch-up hint they showed goes; one they haven't shown yet stays (D338.6).
    public func dismissCatchUpHint() {
        useCases.notices.dismissIfShown()
        pendingCatchUp = useCases.notices.pending()
        catchUpHintAppearedHere = false
        keepsHintAfterLeaving = false
    }

    public var title: String { ScheduledText.title }
    public var overdueHeader: String { ScheduledText.overdue }
    public var dueTodayHeader: String { ScheduledText.dueToday }
    public var upcomingHeader: String { ScheduledText.upcoming }
    public var completedTitle: String { ScheduledText.completed }
    public var emptyTitle: String { ScheduledText.emptyTitle }
    public var emptyMessage: String { ScheduledText.emptyMessage }
    public var addTitle: String { ScheduledText.add }

    public var isEmpty: Bool { listing.board.isEmpty }

    public var overdueRows: [ScheduledRow] {
        listing.board.overdue.map { rows.row($0.item, day: $0.day, kind: .overdue) }
    }

    public var dueTodayRows: [ScheduledRow] {
        listing.board.dueToday.map { rows.row($0.item, day: $0.day, kind: .dueToday) }
    }

    public var upcomingRows: [ScheduledRow] {
        listing.board.upcoming.map { rows.row($0.item, day: $0.day, kind: .upcoming) }
    }

    public var completedRows: [ScheduledRow] {
        listing.board.completed.map { rows.row($0, day: nil, kind: .completed) }
    }

    /// "8 overdue payments need you.", from the occurrences that need the user, plus "Tap one to pay or skip it."
    /// on iOS; `nil` with none (D106, S64, S78, D334.1). It's the first row of Overdue.
    public var overdueHint: String? {
        let count = listing.board.overdueCount
        return count > 0 ? ScheduledText.overdueHint(count, sayingHowToSettle: platform == .iOS) : nil
    }

    /// The most days the catch-up hint lists for one item; beyond that it gives the first and last (D338.1).
    static let listedDays = 5

    /// "3 missed automatic Rent transactions were recorded: 1 Aug, 1 Sep and 1 Oct. Each is recorded only once.",
    /// then "Manual items aren’t recorded for you: each missed one is listed under Overdue." when some are overdue
    /// (D338). The whole hint on every platform (D338.7). `nil` when nothing pending is still on the list.
    public var catchUpHint: String? {
        let rows = rows
        let groups = pendingCatchUp.compactMap { group in
            listing.item(group.itemID).map { (name: rows.shortName(of: $0), group: group) }
        }
        guard !groups.isEmpty else {
            return nil
        }
        let total = groups.reduce(0) { $0 + $1.group.count }
        let recorded: String
        switch groups.count {
        case 1:
            let only = groups[0]
            let days = only.group.days
            if days.count > Self.listedDays, let first = days.first, let last = days.last {
                recorded = ScheduledText.recordedMissed(
                    total,
                    name: only.name,
                    from: rows.dateText(first),
                    to: rows.dateText(last),
                )
            } else {
                let list = days.map(rows.dateText).formatted(.list(type: .and).locale(locale))
                recorded = ScheduledText.recordedMissed(total, name: only.name, days: list)
            }
        case 2:
            let parts = groups.map { ScheduledText.recordedFor($0.group.count, name: $0.name) }
            recorded = ScheduledText.recordedMissed(total, items: parts.formatted(.list(type: .and).locale(locale)))
        default:
            recorded = ScheduledText.recordedMissed(total, itemCount: groups.count)
        }
        var hint = ScheduledText.sentences(recorded, ScheduledText.recordedOnce(total))
        if listing.board.overdueCount > 0 {
            hint = ScheduledText.sentences(hint, ScheduledText.manualStillOverdue)
        }
        return hint
    }

    /// The Mac list's footer under its items when any of them is recorded automatically (D339); `nil` on iOS,
    /// where the form's footnote says it.
    public var automaticFooter: String? {
        guard platform == .macOS else {
            return nil
        }
        let board = listing.board
        let active = (board.overdue + board.dueToday + board.upcoming).map(\.item)
        return active.contains(where: \.processesAutomatically) ? ScheduledText.macAutomaticFooter : nil
    }

    /// The Completed row's count, through the number formatter.
    public var completedCount: String {
        listing.board.completed.count.formatted(.number.locale(locale))
    }

    public func detail(_ itemID: UUID) -> ScheduledItemDetail? {
        guard let item = listing.item(itemID) else {
            return nil
        }
        let presenter = rows
        let (amount, tone) = presenter.amountText(of: item)
        var facts: [ScheduledFact] = []
        if item.type == .transfer {
            facts.append(fact(ScheduledText.fromLabel, listing.account(item.accountID)?.name))
            facts.append(fact(ScheduledText.toLabel, listing.account(item.transferAccountID)?.name))
        } else {
            facts.append(fact(ScheduledText.account, listing.account(item.accountID)?.name))
            facts.append(fact(ScheduledText.category, listing.category(item.categoryID)?.name))
        }
        facts.append(fact(ScheduledText.payee, listing.payee(item.payeeID)?.name))
        facts.append(fact(ScheduledText.repeatLabel, presenter.ruleText(item.repeatRule)))
        facts.append(fact(ScheduledText.starts, ScheduledPresenter.longDate(item.startDay, locale: locale)))
        if item.repeatRule.repeats {
            let ends = item.endDay.map { ScheduledText.endsOn(ScheduledPresenter.dateWithYear($0, locale: locale)) }
            facts.append(fact(ScheduledText.ends, ends ?? ScheduledText.never))
        }
        facts.append(fact(ScheduledText.note, item.note))
        let due =
            listing.board.overdue.filter { $0.item.id == itemID }
            .map { rows.row($0.item, day: $0.day, kind: .overdue) }
            + listing.board.dueToday.filter { $0.item.id == itemID }
            .map {
                rows.row($0.item, day: $0.day, kind: .dueToday)
            }
        // D369: the next unsettled day on the current rule from today, never an overdue day; the overdue ones keep
        // their own rows above (D339, D340).
        let next = ScheduleCalendar.firstOccurrence(of: item, onOrAfter: listing.board.today) { !item.isSettled($0) }
        return ScheduledItemDetail(
            itemID: itemID,
            title: presenter.name(of: item),
            amount: amount,
            tone: tone,
            facts: facts.filter { !$0.value.isEmpty },
            next: next.map { ScheduledText.nextDue(presenter.dateText($0)) }
                ?? ScheduledText.ended(lastDueDay(of: item).map(presenter.dateText) ?? ""),
            due: due,
        )
    }

    /// A completed item's last due date: its last occurrence, or the last one settled.
    private func lastDueDay(of item: ScheduledItem) -> CalendarDay? {
        let through = item.endDay ?? (item.repeatRule.repeats ? listing.board.today : item.startDay)
        let ruled = ScheduleCalendar.occurrences(of: item, through: max(through, item.startDay)).last
        return [ruled, item.settledDays.max()].compactMap { $0 }.max()
    }

    private func fact(_ label: String, _ value: String?) -> ScheduledFact {
        ScheduledFact(label: label, value: value ?? "")
    }

    // MARK: Actions

    /// Pay Now: records the occurrence dated today, keyed to its own due day. A second tap, or another window's,
    /// records nothing (#26 exactly once).
    public func payNow(_ row: ScheduledRow) {
        guard let occurrence = row.occurrence else {
            return
        }
        perform { try useCases.manage.payNow(itemID: row.itemID, occurrence: occurrence) }
    }

    /// Asks before skipping (D334.8, D339): "Skip 15 Oct Electricity?", with the next due date
    /// that stays on the schedule, or that none follows.
    public func confirmSkip(_ row: ScheduledRow) {
        guard let occurrence = row.occurrence, let item = listing.item(row.itemID) else {
            return
        }
        let rows = rows
        let date = rows.dateText(occurrence)
        let next = ScheduleCalendar.adding(days: 1, to: occurrence)
            .flatMap { after in
                ScheduleCalendar.firstOccurrence(of: item, onOrAfter: after, where: { !item.isSettled($0) })
            }
        let message =
            next.map {
                ScheduledText.skipMessage(date: date, next: ScheduledPresenter.dateWithYear($0, locale: locale))
            } ?? ScheduledText.skipLastMessage(date: date)
        confirmation = ScheduledConfirmation(
            action: .skip(itemID: row.itemID, occurrence: occurrence),
            title: ScheduledText.skipTitle(date: date, name: rows.shortName(of: item)),
            message: message,
            confirmTitle: platform == .macOS ? ScheduledText.skip : ScheduledText.skipOccurrence,
            isDestructive: false,
        )
    }

    public func confirmDelete(_ itemID: UUID) {
        guard let item = listing.item(itemID) else {
            return
        }
        confirmation = ScheduledConfirmation(
            action: .delete(itemID: itemID),
            title: ScheduledText.deleteTitle(rows.shortName(of: item)),
            message: ScheduledText.deleteMessage,
            confirmTitle: ScheduledText.delete,
            isDestructive: true,
        )
    }

    /// Runs the confirmed Skip or Delete.
    public func confirm() {
        guard let action = confirmation?.action else {
            return
        }
        confirmation = nil
        switch action {
        case .skip(let itemID, let occurrence):
            perform { try useCases.manage.skip(itemID: itemID, occurrence: occurrence) }
        case .delete(let itemID):
            perform { try useCases.manage.delete(id: itemID) }
        }
    }

    public var cancelTitle: String { CategoryText.cancel }
    public var okayTitle: String { CategoryText.okay }
    public var payNowTitle: String { ScheduledText.payNow }
    /// The item screen's button (D334.8).
    public var skipTitle: String { ScheduledText.skipOccurrence }
    public var editTitle: String { ScheduledText.edit }
    public var deleteTitle: String { ScheduledText.delete }
    /// The row menu: the Mac's items that ask first or open a sheet take an ellipsis; iOS never does (D334.10).
    public var skipMenuTitle: String {
        platform == .macOS ? ScheduledText.skipOccurrenceMenu : ScheduledText.skipOccurrence
    }
    public var editMenuTitle: String { platform == .macOS ? ScheduledText.editMenu : ScheduledText.edit }
    public var deleteMenuTitle: String { platform == .macOS ? ScheduledText.deleteMenu : ScheduledText.delete }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            alert = ScheduledText.saveFailed
        }
        load()
        changed()
    }

    // MARK: Form

    public func openNew() {
        form = makeForm(nil)
    }

    public func openEditor(_ itemID: UUID) {
        guard let item = listing.item(itemID) else {
            return
        }
        form = makeForm(item)
    }

    private func makeForm(_ item: ScheduledItem?) -> ScheduledFormViewModel {
        ScheduledFormViewModel(
            useCases: useCases,
            listing: listing,
            editing: item,
            locale: locale,
            platform: platform,
        ) { [weak self] in
            self?.load()
            self?.changed()
        }
    }
}

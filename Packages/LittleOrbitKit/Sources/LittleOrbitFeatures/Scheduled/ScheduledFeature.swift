import Foundation
import LittleOrbitDomain

/// The use cases the Scheduled screens need, from the composition root.
@MainActor
public struct ScheduledScreenUseCases {
    public var load: any LoadScheduledUseCase
    public var manage: any ManageScheduledUseCase
    public var catchUp: any CatchUpScheduledUseCase
    /// What catch-up recorded while the app was closed, for the list's hint. One per launch, shared by windows.
    public var notices: any ScheduledCatchUpNoticeUseCase
    /// Whether reminders can arrive, and the system prompt the first time 'Notify when due' is turned on.
    public var permission: any NotificationPermissionUseCase
    /// Settings › Scheduled Items › Reminder Time, which the form's footnote names (D340.7).
    public var reminderTime: any ScheduledReminderTimeUseCase

    public init(
        load: any LoadScheduledUseCase,
        manage: any ManageScheduledUseCase,
        catchUp: any CatchUpScheduledUseCase,
        notices: any ScheduledCatchUpNoticeUseCase = ScheduledCatchUpNotices(),
        permission: any NotificationPermissionUseCase = FixedNotificationPermission(),
        reminderTime: any ScheduledReminderTimeUseCase = FixedReminderTime(),
    ) {
        self.load = load
        self.manage = manage
        self.catchUp = catchUp
        self.notices = notices
        self.permission = permission
        self.reminderTime = reminderTime
    }
}

/// A Reminder Time kept for one run only, 09:00 unless set: previews and tests.
@MainActor
public final class FixedReminderTime: ScheduledReminderTimeUseCase {
    private var time: ReminderTime

    public init(_ time: ReminderTime = .standard) {
        self.time = time
    }

    public func reminderTime() -> ReminderTime {
        time
    }

    public func setReminderTime(_ time: ReminderTime) {
        self.time = time
    }
}

/// Everything the Scheduled screens need (#26), built once by the composition root. It records due automatic
/// occurrences, each once, and counts the home row and badge (D106). Each window makes its own list model.
@MainActor
public final class ScheduledFeature: PlannedItemsSource {
    public let useCases: ScheduledScreenUseCases
    /// Reminder taps waiting for a window to open their item (S33).
    public let reminderTaps = ScheduledReminderTaps()
    private let updates: LedgerUpdates?
    /// Keeps the pending reminders current (D340.7); `nil` where nothing posts notifications.
    private let reminders: ScheduledReminders?
    let locale: Locale
    /// Called when a catch-up couldn't run or left some items unrecorded; the App logs it with no user data.
    private let onCatchUpProblem: (ScheduledCatchUpProblem) -> Void
    /// The clock-ahead line is logged once per launch, not on every activation (Tech Architect NB 1). The feature
    /// is built once per launch.
    private var reportedCreatedAfterToday = false
    /// Removes the restore handler if this feature is ever replaced while `updates` lives on.
    private var ledgerReplacedHandler: LedgerUpdates.ReplacedHandler?
    /// The card for watch Pay and Skip requests the iPhone didn't apply (D374, D376), shared by every window's
    /// list; `nil` with no watch link (the Mac).
    public let watchNotices: WatchRequestNoticeViewModel?

    /// `updates` tells every window to reload after a scheduled change, as a transaction change does. Every change
    /// and restore it reports also reschedules `reminders`: a Pay, Skip, edit or delete, an account delete, and
    /// their Undo and Redo (D340.7).
    public init(
        useCases: ScheduledScreenUseCases,
        updates: LedgerUpdates? = nil,
        reminders: ScheduledReminders? = nil,
        locale: Locale = .current,
        watchNotices: WatchRequestNoticeViewModel? = nil,
        onCatchUpProblem: @escaping (ScheduledCatchUpProblem) -> Void = { _ in },
    ) {
        self.useCases = useCases
        self.watchNotices = watchNotices
        self.updates = updates
        self.reminders = reminders
        self.locale = locale
        self.onCatchUpProblem = onCatchUpProblem
        // A restore replaces the ledger, so a pending catch-up hint could name days it no longer has (Tech
        // Architect NB 1).
        ledgerReplacedHandler = updates?.onLedgerReplaced { [notices = useCases.notices] in notices.clear() }
        if let reminders {
            updates?.onChanged { reminders.refresh() }
        }
    }

    /// Records every due occurrence of the automatic items, each once, dated on its own due day. The App calls it
    /// at launch before the accounts and badge load (`atLaunch`), and whenever the app becomes active. It's outside
    /// undo history (D187.2). Running it twice, from two windows or after a clock change records nothing more.
    @discardableResult
    public func catchUp(atLaunch: Bool) -> ScheduledCatchUp? {
        // At launch and on every activation, so a day or time zone change while away is picked up (S23).
        defer { reminders?.refresh() }
        let result: ScheduledCatchUp
        do {
            result = try useCases.catchUp.catchUp(atLaunch: atLaunch)
        } catch {
            onCatchUpProblem(.failed(error))
            return nil
        }
        if !result.failedItemIDs.isEmpty {
            onCatchUpProblem(.someNotRecorded)
        }
        if !result.createdAfterTodayItemIDs.isEmpty && !reportedCreatedAfterToday {
            reportedCreatedAfterToday = true
            onCatchUpProblem(.createdAfterToday)
        }
        // The list's info hint says what was recorded while the app was closed, until the list has shown it.
        useCases.notices.add(result)
        if result.changedLedger {
            updates?.changed()
        }
        return result
    }

    /// Settings › Scheduled Items › Reminder Time. A change reschedules every reminder at the new time (S10).
    public func makeReminderSettings() -> ScheduledReminderSettingsViewModel {
        ScheduledReminderSettingsViewModel(useCase: useCases.reminderTime) { [weak reminders] in
            reminders?.refresh()
        }
    }

    public func plannedItemCounts() -> PlannedItemCounts {
        guard let board = try? useCases.load.listing().board else {
            return PlannedItemCounts()
        }
        return PlannedItemCounts(scheduledItemCount: board.itemCount, overdueOccurrenceCount: board.overdueCount)
    }

    /// The accounts the store's currency lock counts, Completed and hidden items included, for Edit Account's lock
    /// (D381.3, #207 B2): the same set the store checks, so the form never shows unlocked what the store refuses.
    /// Throws when the store can't be read.
    public func scheduledAccountIDs() throws -> Set<UUID> {
        try useCases.load.currencyLockedAccountIDs()
    }

    /// The item a reminder tap that names none opens, for Debug › Tap Scheduled Reminder (S33): the first item with
    /// Notify when due on, else the first item, in the list's order. `nil` with no items, or when the store can't
    /// be read.
    public func defaultReminderItemID() -> UUID? {
        guard let items = try? useCases.load.listing().board.items else {
            return nil
        }
        return (items.first(where: \.notifiesWhenDue) ?? items.first)?.id
    }

    /// The items an account delete deletes with it (D288). Throws when the store can't be read (n5).
    public func scheduledItems() throws -> [ScheduledItem] {
        try useCases.load.listing().board.items
    }

    public func movedOccurrenceCount(toAccount accountID: UUID) -> Int {
        (try? useCases.load.movedOccurrenceCount(toAccount: accountID)) ?? 0
    }

    public func makeList() -> ScheduledListViewModel {
        ScheduledListViewModel(useCases: useCases, locale: locale) { [weak updates] in updates?.changed() }
    }

    /// The ledger revision every window follows, so a screen reloads after a change made elsewhere.
    public var revision: Int {
        updates?.revision ?? 0
    }

    /// Stops clearing the catch-up hint on restore, for a feature that's replaced while `updates` lives on.
    public func stopFollowingRestores() {
        guard let ledgerReplacedHandler else {
            return
        }
        updates?.removeLedgerReplacedHandler(ledgerReplacedHandler)
        self.ledgerReplacedHandler = nil
    }
}

/// Why a catch-up needs a log line. Never carries names, amounts or paths.
public enum ScheduledCatchUpProblem {
    case failed(any Error)
    case someNotRecorded
    /// Some items' creation day is after today: the device clock was ahead when they were made.
    case createdAfterToday
}

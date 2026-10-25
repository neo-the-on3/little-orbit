import Foundation

/// Keeps the pending 'Notify when due' reminders matching the ledger (#26, D340.7). The App calls it at launch and
/// on becoming active, and the screens after every change and a Reminder Time change.
@MainActor
public protocol ScheduleRemindersUseCase {
    /// Replaces the pending reminders with the nearest ones the ledger has now: the user's paid and skipped
    /// occurrences' and deleted items' reminders go, and the rest are scheduled again at the current Reminder Time.
    /// An automatic occurrence the app recorded keeps its reminder (S81, D354.1).
    func reschedule() async throws
}

/// Settings › Scheduled Items › Reminder Time (D341.4).
@MainActor
public protocol ScheduledReminderTimeUseCase {
    func reminderTime() -> ReminderTime
    /// Keeps `time`. Rescheduling is the caller's next step.
    func setReminderTime(_ time: ReminderTime)
}

/// Whether reminders can arrive, and the system prompt the first time 'Notify when due' is turned on.
@MainActor
public protocol NotificationPermissionUseCase {
    func permission() async -> NotificationPermission
    func requestPermission() async -> NotificationPermission
}

/// A fixed answer and no prompt, for previews and the screens' tests.
public struct FixedNotificationPermission: NotificationPermissionUseCase {
    private let value: NotificationPermission

    public init(_ value: NotificationPermission = .allowed) {
        self.value = value
    }

    public func permission() async -> NotificationPermission {
        value
    }

    public func requestPermission() async -> NotificationPermission {
        value
    }
}

/// The default reminder use cases over the schedule repository, the system's notifications and the kept time. The
/// clock and zone are read on every call, like `DefaultScheduledUseCases`, so a zone change is picked up (S23).
@MainActor
public struct DefaultScheduledReminderUseCases: ScheduleRemindersUseCase {
    private let repository: any ScheduleRepository
    private let notifications: any ScheduledNotificationScheduling
    private let times: any ScheduledReminderTimeStore
    private let wording: any ScheduledReminderWording
    private let now: @MainActor () -> Date
    private let timeZone: @MainActor () -> TimeZone

    public init(
        repository: any ScheduleRepository,
        notifications: any ScheduledNotificationScheduling,
        times: any ScheduledReminderTimeStore,
        wording: any ScheduledReminderWording,
        now: @escaping @MainActor () -> Date,
        timeZone: @escaping @MainActor () -> TimeZone,
    ) {
        self.repository = repository
        self.notifications = notifications
        self.times = times
        self.wording = wording
        self.now = now
        self.timeZone = timeZone
    }

    public func reminderTime() -> ReminderTime {
        times.reminderTime()
    }

    public func setReminderTime(_ time: ReminderTime) {
        times.setReminderTime(time)
    }

    public func permission() async -> NotificationPermission {
        await notifications.permission()
    }

    public func requestPermission() async -> NotificationPermission {
        await notifications.requestPermission()
    }

    /// Items on a deleted account are left out with the rest of the board (D288.1), so their reminders go too, and
    /// come back with Undo while their times are still ahead. Without permission nothing is scheduled, and any
    /// pending reminders are removed.
    public func reschedule() async throws {
        let ledger = try repository.scheduleLedger()
        let zone = timeZone()
        let current = now()
        let planned: [ScheduledReminder]
        if await notifications.permission() == .allowed {
            planned = ScheduledReminderPlanner.plan(
                LedgerBook.activeScheduledItems(in: ledger),
                now: current,
                timeZone: zone,
                time: times.reminderTime(),
            )
        } else {
            planned = []
        }
        let wanted = Set(planned.map(\.id))
        let stale = await notifications.pendingIdentifiers()
            .filter { $0.hasPrefix(ScheduledReminder.identifierPrefix) && !wanted.contains($0) }
        if !stale.isEmpty {
            notifications.removePending(stale)
        }
        guard !planned.isEmpty else {
            return
        }
        let listing = ScheduledListing(
            board: ScheduledBoard(today: TransactionTiming.today(current, timeZone: zone)),
            accounts: ledger.accountsVisible(),
            categories: ledger.categoriesVisible(),
            payees: ledger.payeesVisible(),
        )
        try await notifications.add(
            planned.map { reminder in
                ScheduledNotificationRequest(
                    id: reminder.id,
                    itemID: reminder.item.id,
                    day: reminder.day,
                    time: reminder.time,
                    content: wording.content(for: reminder, in: listing),
                )
            }
        )
    }
}

extension DefaultScheduledReminderUseCases: ScheduledReminderTimeUseCase, NotificationPermissionUseCase {}

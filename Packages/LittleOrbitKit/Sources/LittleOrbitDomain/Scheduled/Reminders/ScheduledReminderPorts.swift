import Foundation

/// Whether the app may post notifications, as the system last said.
public enum NotificationPermission: Hashable, Sendable {
    /// Never asked: turning 'Notify when due' on shows the system prompt.
    case notDetermined
    case allowed
    case denied
}

/// The title and body a reminder shows. The screens word it; Domain holds no user-facing text.
public struct ScheduledNotificationContent: Hashable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// One local notification to schedule: a planned reminder with its words. It arrives on `day` at `time` in the
/// zone the device is in then, so a time zone change keeps 09:00 local (S23).
public struct ScheduledNotificationRequest: Hashable, Sendable, Identifiable {
    public var id: String
    public var itemID: UUID
    public var day: CalendarDay
    public var time: ReminderTime
    public var content: ScheduledNotificationContent

    public init(
        id: String,
        itemID: UUID,
        day: CalendarDay,
        time: ReminderTime,
        content: ScheduledNotificationContent,
    ) {
        self.id = id
        self.itemID = itemID
        self.day = day
        self.time = time
        self.content = content
    }
}

/// The system's local notifications, behind a port: the App's adapter wraps `UNUserNotificationCenter`.
@MainActor
public protocol ScheduledNotificationScheduling: AnyObject {
    func permission() async -> NotificationPermission
    /// Shows the system prompt when the user hasn't been asked yet, and returns the answer.
    func requestPermission() async -> NotificationPermission
    /// Every pending request's identifier, including ones that aren't reminders.
    func pendingIdentifiers() async -> [String]
    /// Schedules each request. One with the identifier of a pending request replaces it.
    func add(_ requests: [ScheduledNotificationRequest]) async throws
    func removePending(_ identifiers: [String])
}

/// Words a planned reminder, with the accounts, categories and payees its item's name may use.
@MainActor
public protocol ScheduledReminderWording {
    func content(for reminder: ScheduledReminder, in listing: ScheduledListing) -> ScheduledNotificationContent
}

/// Where the reminder time is kept: app settings, not the ledger, so no backup holds it and the schema doesn't
/// change.
@MainActor
public protocol ScheduledReminderTimeStore: AnyObject {
    func reminderTime() -> ReminderTime
    func setReminderTime(_ time: ReminderTime)
}

/// A reminder time for one run only: tests and previews.
@MainActor
public final class InMemoryScheduledReminderTimeStore: ScheduledReminderTimeStore {
    private var stored: ReminderTime

    public init(_ time: ReminderTime = .standard) {
        stored = time
    }

    public func reminderTime() -> ReminderTime {
        stored
    }

    public func setReminderTime(_ time: ReminderTime) {
        stored = time
    }
}

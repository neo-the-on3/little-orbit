import Foundation
import LittleOrbitDomain

/// Settings › Scheduled Items › Reminder Time in this device's app settings (D341.4), as minutes after midnight. It
/// isn't ledger data, so no backup holds it and the store's schema doesn't change. Nothing kept means 09:00.
@MainActor
public final class UserDefaultsScheduledReminderTime: ScheduledReminderTimeStore {
    static let key = "scheduled.reminderTime.minutesAfterMidnight"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func reminderTime() -> ReminderTime {
        guard let minutes = defaults.object(forKey: Self.key) as? Int else {
            return .standard
        }
        return ReminderTime(minutesAfterMidnight: minutes)
    }

    public func setReminderTime(_ time: ReminderTime) {
        defaults.set(time.minutesAfterMidnight, forKey: Self.key)
    }
}

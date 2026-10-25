import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// D341.4: Reminder Time is kept in app settings, 09:00 until it's changed.
@MainActor
@Suite("Reminder Time in app settings", .timeLimit(.minutes(2)))
struct UserDefaultsScheduledReminderTimeTests {
    private func defaults() throws -> (UserDefaults, String) {
        let name = "scheduled-reminder-time-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test("Nothing kept reads 09:00")
    func standard() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(UserDefaultsScheduledReminderTime(defaults: defaults).reminderTime() == .standard)
    }

    @Test("A changed time survives a relaunch")
    func roundTrip() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        UserDefaultsScheduledReminderTime(defaults: defaults).setReminderTime(ReminderTime(hour: 18, minute: 30))
        let relaunched = UserDefaultsScheduledReminderTime(defaults: defaults)
        #expect(relaunched.reminderTime() == ReminderTime(hour: 18, minute: 30))
        #expect(defaults.integer(forKey: UserDefaultsScheduledReminderTime.key) == 18 * 60 + 30)
    }

    @Test("An out-of-range value is clamped, never an impossible time")
    func clamped() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(5_000, forKey: UserDefaultsScheduledReminderTime.key)
        #expect(
            UserDefaultsScheduledReminderTime(defaults: defaults).reminderTime() == ReminderTime(hour: 23, minute: 59)
        )
    }
}

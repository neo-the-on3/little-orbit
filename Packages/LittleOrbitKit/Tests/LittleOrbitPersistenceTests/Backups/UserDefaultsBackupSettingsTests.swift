import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// D195.4: N and M are app settings on this device.
@Suite("Backup settings")
struct UserDefaultsBackupSettingsTests {
    private func defaults() throws -> (UserDefaults, String) {
        let name = "backup-settings-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test("They start at 7 and 12, and keep what's set")
    func roundTrip() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = UserDefaultsBackupSettings(defaults: defaults)
        #expect(settings.retention() == .default)
        settings.setRetention(BackupRetention(recentAutomatic: 3, monthlyMonths: 0))
        #expect(
            UserDefaultsBackupSettings(defaults: defaults).retention()
                == BackupRetention(recentAutomatic: 3, monthlyMonths: 0)
        )
    }

    @Test("A stored value outside the range is clamped")
    func clamped() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(99, forKey: UserDefaultsBackupSettings.recentKey)
        defaults.set(-1, forKey: UserDefaultsBackupSettings.monthlyKey)
        #expect(
            UserDefaultsBackupSettings(defaults: defaults).retention()
                == BackupRetention(recentAutomatic: 30, monthlyMonths: 0)
        )
    }
}

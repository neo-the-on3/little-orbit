import Foundation
import LittleOrbitDomain

/// N and M for backups, in this device's app settings (D195.4). They aren't ledger data: no backup holds them and
/// a restore leaves them as they are.
public final class UserDefaultsBackupSettings: BackupSettingsStore, @unchecked Sendable {
    static let recentKey = "backups.retention.recentAutomatic"
    static let monthlyKey = "backups.retention.monthlyMonths"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func retention() -> BackupRetention {
        let fallback = BackupRetention.default
        return BackupRetention(
            recentAutomatic: (defaults.object(forKey: Self.recentKey) as? Int) ?? fallback.recentAutomatic,
            monthlyMonths: (defaults.object(forKey: Self.monthlyKey) as? Int) ?? fallback.monthlyMonths,
        )
    }

    public func setRetention(_ retention: BackupRetention) {
        defaults.set(retention.recentAutomatic, forKey: Self.recentKey)
        defaults.set(retention.monthlyMonths, forKey: Self.monthlyKey)
    }
}

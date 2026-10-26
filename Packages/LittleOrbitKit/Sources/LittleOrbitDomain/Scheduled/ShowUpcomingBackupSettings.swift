import Foundation

/// "Show upcoming" in every backup (D80, D348.3): a shared preference, written with its current value and put back
/// on restore. A backup with no value, as every one before D348 is, restores as On (D348.4).
@MainActor
public final class ShowUpcomingBackupSettings: BackupSharedSettingsStore {
    private let store: any ShowUpcomingSettingStore

    public init(store: any ShowUpcomingSettingStore) {
        self.store = store
    }

    public func backupSharedSettings() -> BackupSharedSettings {
        BackupSharedSettings(showUpcoming: store.showsUpcoming)
    }

    public func restoreSharedSettings(_ settings: BackupSharedSettings) {
        store.showsUpcoming = settings.showUpcoming ?? true
    }
}

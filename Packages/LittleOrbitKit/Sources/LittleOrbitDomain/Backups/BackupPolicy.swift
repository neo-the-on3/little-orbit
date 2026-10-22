import Foundation

/// When an automatic backup is made and which ones are pruned (D62, D96.3, D116.3, D118.1, D118.2).
public enum BackupPolicy {
    /// The number of automatic backups kept. Manual and Before restore backups are never pruned.
    public static let automaticRetention = 14

    /// Whether an automatic backup already exists for `now`'s local calendar day in `timeZone`.
    public static func hasAutomaticBackup(on now: Date, timeZone: TimeZone, in catalog: BackupCatalog) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return catalog.records.contains { record in
            record.kind == .automatic && calendar.isDate(record.createdAt, inSameDayAs: now)
        }
    }

    /// Whether the launch or background trigger should make an automatic backup now.
    ///
    /// - At most one automatic backup per local calendar day. A Before restore backup isn't the day's automatic one.
    /// - None when the newest backup that still exists, of any kind, already reflects the data (D116.3, D118.1).
    /// - None when the data is what a restore left in place and nothing changed since (D96.3, D118.2).
    /// - None for an empty ledger that has never been backed up: there's nothing to protect yet (D179.3).
    public static func needsAutomaticBackup(
        now: Date,
        timeZone: TimeZone,
        catalog: BackupCatalog,
        currentFingerprint: String,
        ledgerIsEmpty: Bool,
    ) -> Bool {
        if hasAutomaticBackup(on: now, timeZone: timeZone, in: catalog) {
            return false
        }
        if let newest = catalog.newestFirst.first, newest.fingerprint == currentFingerprint {
            return false
        }
        if catalog.restoredFingerprint == currentFingerprint {
            return false
        }
        if catalog.records.isEmpty && ledgerIsEmpty {
            return false
        }
        return true
    }

    /// Whether a ledger has nothing to protect yet (D179.3): no accounts and no transactions. Seeded default
    /// categories alone don't count as data.
    public static func isEmpty(_ ledger: LedgerSnapshot) -> Bool {
        ledger.accounts.isEmpty && ledger.transactions.isEmpty
    }

    /// The automatic backups to remove once a new one is stored: all but the newest `automaticRetention`.
    public static func automaticBackupsToPrune(in catalog: BackupCatalog) -> [BackupRecord] {
        Array(catalog.newestFirst.filter { $0.kind == .automatic }.dropFirst(automaticRetention))
    }
}

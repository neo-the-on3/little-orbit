import Foundation

/// A backup's name index: the identity behind the Finder-style ` 2`, ` 3` suffix of its exported name (D173.11).
///
/// The index is chosen once, when the backup is made, from the backups in the list at that moment, so the lowest
/// free one is used and nothing is renamed later (D174). It's stored in the manifest. Formatting
/// the name itself is presentation and lives in `LittleOrbitFeatures` (`BackupPresentation.fileName`).
public enum BackupNaming {
    /// The name index for a backup made at `createdAt`: 1 for the plain name, otherwise the lowest free suffix
    /// among `existing` backups made in the same minute.
    public static func nameIndex(for createdAt: Date, existing: [BackupRecord]) -> Int {
        let minute = minuteNumber(createdAt)
        let used = Set(existing.filter { minuteNumber($0.createdAt) == minute }.map(\.nameIndex))
        var index = 1
        while used.contains(index) {
            index += 1
        }
        return index
    }

    /// Minutes since 1970. Every time zone offset is a whole number of minutes, so the same minute in UTC is the
    /// same minute on the device's clock.
    public static func minuteNumber(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 / 60).rounded(.down))
    }
}

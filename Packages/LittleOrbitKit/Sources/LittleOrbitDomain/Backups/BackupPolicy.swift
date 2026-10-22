import Foundation

/// How many automatic backups are kept (D195.4). A device setting: it isn't part of a backup, so a restore never
/// changes it.
public struct BackupRetention: Equatable, Sendable, Codable {
    /// The most recent automatic backups kept: N, 1–30.
    public var recentAutomatic: Int
    /// The months, the current one included, whose first automatic backup is kept: M, 0–24, where 0 is off.
    public var monthlyMonths: Int

    public static let recentAutomaticRange = 1...30
    public static let monthlyMonthsRange = 0...24
    public static let `default` = BackupRetention(recentAutomatic: 7, monthlyMonths: 12)

    /// Values outside the ranges are clamped into them.
    public init(recentAutomatic: Int, monthlyMonths: Int) {
        self.recentAutomatic = recentAutomatic.clamped(to: Self.recentAutomaticRange)
        self.monthlyMonths = monthlyMonths.clamped(to: Self.monthlyMonthsRange)
    }

    /// Whether `self` keeps fewer of either than `other`, so changing to it may delete backups (D195.5).
    public func isLower(than other: BackupRetention) -> Bool {
        recentAutomatic < other.recentAutomatic || monthlyMonths < other.monthlyMonths
    }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// A backup's month, `YYYY-MM`, fixed in the device's time zone when it's made (D196.2).
public enum BackupMonth {
    /// `2026-11` for 00:30 IST on 1 Nov 2026 in Asia/Kolkata (L26).
    public static func string(for date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = String(parts.year ?? 0)
        let month = String(parts.month ?? 1)
        return String(repeating: "0", count: max(0, 4 - year.count)) + year + "-"
            + (month.count < 2 ? "0" : "") + month
    }

    /// Months since year 0, or `nil` when `string` isn't `YYYY-MM`.
    static func number(_ string: String) -> Int? {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month)
        else {
            return nil
        }
        return year * 12 + month - 1
    }

    static func number(of date: Date, in timeZone: TimeZone) -> Int {
        number(string(for: date, in: timeZone)) ?? 0
    }
}

/// When an automatic backup is made and which ones are pruned (D62, D96.3, D116.3, D118.1, D118.2, D195.4, D196).
public enum BackupPolicy {
    /// Whether a restorable automatic backup already exists for `now`'s local calendar day in `timeZone`. A damaged
    /// or newer-format one doesn't count, so the day still gets a good one (D196.3).
    public static func hasAutomaticBackup(on now: Date, timeZone: TimeZone, in catalog: BackupCatalog) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return catalog.records.contains { record in
            record.isRestorable && record.kind == .automatic && calendar.isDate(record.createdAt, inSameDayAs: now)
        }
    }

    /// Whether the launch or background trigger should make an automatic backup now.
    ///
    /// - At most one automatic backup per local calendar day. A Before restore backup isn't the day's automatic one.
    /// - None when the newest restorable backup, of any kind, already reflects the data (D116.3, D118.1).
    /// - None when the data is what a restore left in place and nothing changed since (D96.3, D118.2).
    /// - None for an empty ledger that has never been backed up: there's nothing to protect yet (D179.3).
    public static func needsAutomaticBackup(
        now: Date,
        timeZone: TimeZone,
        catalog: BackupCatalog,
        currentFingerprint: String,
        ledgerIsEmpty: Bool,
    ) -> Bool {
        let restorable = catalog.restorable
        if hasAutomaticBackup(on: now, timeZone: timeZone, in: restorable) {
            return false
        }
        if let newest = restorable.newestFirst.first, newest.fingerprint == currentFingerprint {
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

    /// The automatic backups `retention` doesn't keep at `now` (D195.4, D196, D197.2, L7–L10, L26–L36):
    /// - only restorable automatic backups count; damaged and newer-format ones are never pruned, never counted
    ///   toward N and never a month's keeper
    /// - the `recentAutomatic` newest are kept
    /// - so is the earliest of each month, for the current month in `timeZone` and the `monthlyMonths - 1` before
    ///   it. A backup's month is the one its manifest records; only one without it uses its creation moment in
    ///   `timeZone` (L27, L28)
    /// - Manual and Before restore backups are never pruned and don't count toward either number
    /// - and never the last restorable backup (L33).
    ///
    /// Oldest first. Pure, with the clock and time zone injected.
    public static func automaticBackupsToPrune(
        in records: [BackupRecord],
        retention: BackupRetention,
        now: Date,
        timeZone: TimeZone,
    ) -> [BackupRecord] {
        let automatic = records.filter { $0.isRestorable && $0.kind == .automatic }
            .sorted { ($0.createdAt, $0.nameIndex) > ($1.createdAt, $1.nameIndex) }
        var kept = Set(automatic.prefix(retention.recentAutomatic).map(\.id))
        let current = BackupMonth.number(of: now, in: timeZone)
        var keeperOfMonth: [Int: BackupRecord] = [:]
        for record in automatic.reversed() {
            let month =
                record.month.flatMap(BackupMonth.number) ?? BackupMonth.number(of: record.createdAt, in: timeZone)
            if current - month < retention.monthlyMonths, month <= current, keeperOfMonth[month] == nil {
                keeperOfMonth[month] = record
            }
        }
        kept.formUnion(keeperOfMonth.values.map(\.id))
        let prune = automatic.reversed().filter { !kept.contains($0.id) }
        return keepingARestorableBackup(prune, of: records)
    }

    /// `prune` without the one backup cleanup must keep when no restorable backup would be left otherwise: the
    /// newest restorable backup in `prune` (D195.4, D196.3, D197a.2, L33, L43). Only restorable backups count;
    /// damaged and newer-format ones never do.
    public static func keepingARestorableBackup(_ prune: [BackupRecord], of records: [BackupRecord]) -> [BackupRecord] {
        let pruned = Set(prune.map(\.id))
        if records.contains(where: { $0.isRestorable && !pruned.contains($0.id) }) {
            return prune
        }
        guard let keep = BackupCatalog(records: prune.filter(\.isRestorable)).newestFirst.first else {
            return prune
        }
        return prune.filter { $0.id != keep.id }
    }
}

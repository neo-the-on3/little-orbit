import Foundation
import LittleOrbitDomain
import Testing

/// D195.4 and L7–L10, L33: which automatic backups cleanup keeps, as a pure function with an injected clock.
@Suite("Backup retention", .timeLimit(.minutes(2)))
struct BackupRetentionTests {
    private let zone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// 09:00 IST on the given day.
    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .now
    }

    private func automatic(_ date: Date) -> BackupRecord {
        BackupRecord(kind: .automatic, createdAt: date)
    }

    private func prune(
        _ records: [BackupRecord],
        at now: Date,
        _ retention: BackupRetention = .default,
    ) -> [BackupRecord] {
        BackupPolicy.automaticBackupsToPrune(in: records, retention: retention, now: now, timeZone: zone)
    }

    @Test("The defaults are 7 recent and 12 months, within 1–30 and 0–24 (L11)")
    func defaults() {
        #expect(BackupRetention.default == BackupRetention(recentAutomatic: 7, monthlyMonths: 12))
        #expect(BackupRetention.recentAutomaticRange == 1...30)
        #expect(BackupRetention.monthlyMonthsRange == 0...24)
        #expect(
            BackupRetention(recentAutomatic: 0, monthlyMonths: 99)
                == BackupRetention(recentAutomatic: 1, monthlyMonths: 24)
        )
    }

    @Test("1–8 Oct are all kept; after 9 Oct only 2 Oct goes (L7)")
    func october() {
        let eight = (1...8).map { automatic(day(2026, 10, $0)) }
        #expect(prune(eight, at: day(2026, 10, 8)).isEmpty)
        let ninth = automatic(day(2026, 10, 9))
        #expect(prune(eight + [ninth], at: day(2026, 10, 9)).map(\.id) == [eight[1].id])
    }

    @Test("With a Manual backup on 1 Oct, 2 Oct is October's keeper (L7 variant)")
    func manualIsNotTheKeeper() {
        let manual = BackupRecord(kind: .manual, createdAt: day(2026, 10, 1))
        let fromSecond = (2...9).map { automatic(day(2026, 10, $0)) }
        #expect(prune([manual] + fromSecond, at: day(2026, 10, 9)).isEmpty)
        let tenth = automatic(day(2026, 10, 10))
        #expect(prune([manual] + fromSecond + [tenth], at: day(2026, 10, 10)).map(\.id) == [fromSecond[1].id])
    }

    @Test("A daily backup for a year leaves 16–22 Oct 2026 and the first of Nov 2025 to Oct 2026 (L8)")
    func aYearOfDailyBackups() throws {
        let start = day(2025, 10, 1)
        let end = day(2026, 10, 22)
        var records: [BackupRecord] = []
        var date = start
        while date <= end {
            records.append(automatic(date))
            date = try #require(calendar.date(byAdding: .day, value: 1, to: date))
        }
        let pruned = Set(prune(records, at: end).map(\.id))
        let kept = records.filter { !pruned.contains($0.id) }.map(\.createdAt)
        let recent = (16...22).map { day(2026, 10, $0) }
        let keepers = (0..<12)
            .map { offset in
                calendar.date(byAdding: .month, value: offset, to: day(2025, 11, 1)) ?? .now
            }
        #expect(Set(kept) == Set(recent + keepers))
        #expect(kept.count == 19)
        #expect(pruned.contains(records[0].id))
    }

    @Test("If the first backup of a month was deleted, the earliest remaining one is the keeper (L9)")
    func earliestRemaining() {
        let november = [automatic(day(2025, 11, 3)), automatic(day(2025, 11, 9))]
        let recent = (1...7).map { automatic(day(2026, 10, 10 + $0)) }
        let pruned = prune(november + recent, at: day(2026, 10, 17))
        #expect(pruned.map(\.id) == [november[1].id])
    }

    @Test("Months are local: 23:30 IST on 31 Oct counts for October (L9, D133)")
    func localMonth() {
        let lateOctober = automatic(day(2026, 10, 31, hour: 23, minute: 30))
        let november = automatic(day(2026, 11, 1, hour: 8))
        let retention = BackupRetention(recentAutomatic: 1, monthlyMonths: 2)
        // Both are their month's keeper. In UTC both would be in October, and only one would be kept.
        #expect(prune([lateOctober, november], at: day(2026, 11, 1, hour: 9), retention).isEmpty)
    }

    @Test("Manual and Before restore backups are never pruned and don't count, whatever N and M are (L10)")
    func manualAndBeforeRestore() {
        let old = day(2025, 1, 5)
        let others =
            (0..<3).map { BackupRecord(kind: .manual, createdAt: old + Double($0) * 60) }
            + (0..<2).map { BackupRecord(kind: .beforeRestore, createdAt: old + Double($0) * 120) }
        let automatics = (1...10).map { automatic(day(2026, 10, $0)) }
        for retention in [BackupRetention.default, BackupRetention(recentAutomatic: 1, monthlyMonths: 0)] {
            let pruned = Set(prune(others + automatics, at: day(2026, 10, 10), retention).map(\.id))
            #expect(others.allSatisfy { !pruned.contains($0.id) })
        }
        let strict = prune(
            others + automatics,
            at: day(2026, 10, 10),
            BackupRetention(recentAutomatic: 1, monthlyMonths: 0),
        )
        #expect(strict.count == 9)
        #expect(!strict.contains { $0.id == automatics.last?.id })
    }

    @Test("Monthly Backups off keeps only the recent ones")
    func monthlyOff() {
        let records = (1...9).map { automatic(day(2026, 10, $0)) }
        let pruned = prune(records, at: day(2026, 10, 9), BackupRetention(recentAutomatic: 7, monthlyMonths: 0))
        #expect(pruned.map(\.id) == records.prefix(2).map(\.id))
    }

    @Test("The retention function never deletes the last undamaged backup, whatever N and M are (L33)")
    func keepsARestorableBackup() {
        let good = automatic(day(2026, 9, 1))
        let damaged = (2...8).map { BackupRecord(kind: .automatic, createdAt: day(2026, 9, $0), condition: .damaged) }
        let newer = BackupRecord(kind: .automatic, createdAt: day(2026, 9, 9), condition: .newerFormat)
        let records = [good] + damaged + [newer]
        // A prune list that would take the only restorable backup gives it back.
        #expect(BackupPolicy.keepingARestorableBackup([good], of: records).isEmpty)
        // With another restorable backup left, the prune goes ahead.
        let manual = BackupRecord(kind: .manual, createdAt: day(2026, 9, 10))
        #expect(BackupPolicy.keepingARestorableBackup([good], of: records + [manual]) == [good])
    }

    @Test("Only the newest restorable backup in the prune is kept back (L33)")
    func keepsOnlyOne() {
        let records =
            (1...3).map { automatic(day(2026, 9, $0)) }
            + [BackupRecord(kind: .automatic, createdAt: day(2026, 9, 4), condition: .damaged)]
        let kept = BackupPolicy.keepingARestorableBackup(Array(records.prefix(3)), of: records)
        #expect(kept.map(\.id) == [records[0].id, records[1].id])
    }

    @Test("Lowering either number is lowering (D195.5)")
    func lowering() {
        let base = BackupRetention.default
        #expect(BackupRetention(recentAutomatic: 3, monthlyMonths: 12).isLower(than: base))
        #expect(BackupRetention(recentAutomatic: 7, monthlyMonths: 11).isLower(than: base))
        #expect(!BackupRetention(recentAutomatic: 8, monthlyMonths: 12).isLower(than: base))
    }
}

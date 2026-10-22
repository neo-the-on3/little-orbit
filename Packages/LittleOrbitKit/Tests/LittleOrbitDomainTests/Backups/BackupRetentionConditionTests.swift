import Foundation
import LittleOrbitDomain
import Testing

/// D196 and D197.2: a backup's recorded month, and damaged and newer-format backups in retention (L26–L33, L36).
@Suite("Backup retention: months, damaged and newer-format backups", .timeLimit(.minutes(2)))
struct BackupRetentionConditionTests {
    private let kolkata = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private func moment(_ month: Int, _ day: Int, hour: Int = 10, minute: Int = 0, year: Int = 2026) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = kolkata
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
            ?? .now
    }

    /// An automatic backup made in Kolkata, with the month its manifest records.
    private func automatic(_ date: Date, _ condition: BackupCondition = .restorable) -> BackupRecord {
        BackupRecord(
            kind: .automatic,
            createdAt: date,
            month: BackupMonth.string(for: date, in: kolkata),
            condition: condition,
        )
    }

    @Test("00:30 IST on 1 Nov 2026 is month 2026-11, written as YYYY-MM (L26)")
    func monthString() {
        let date = moment(11, 1, hour: 0, minute: 30)
        #expect(BackupMonth.string(for: date, in: kolkata) == "2026-11")
        #expect(BackupMonth.string(for: date, in: .gmt) == "2026-10")
        #expect(BackupMonth.string(for: moment(3, 9, year: 987), in: kolkata) == "0987-03")
    }

    @Test("After a move to Los Angeles, cleanup keeps the recorded months' keepers (L27)")
    func recordedMonthAfterTimeZoneChange() {
        let october = automatic(moment(10, 31))
        let november = automatic(moment(11, 1, hour: 0, minute: 30))
        let second = automatic(moment(11, 2))
        let next = automatic(moment(11, 3))
        let retention = BackupRetention(recentAutomatic: 1, monthlyMonths: 12)
        let pruned = BackupPolicy.automaticBackupsToPrune(
            in: [october, november, second, next],
            retention: retention,
            now: moment(11, 3, hour: 11),
            timeZone: losAngeles,
        )
        // In Los Angeles 1 Nov 00:30 IST is still 31 Oct; recomputing would make it October's and delete it.
        #expect(pruned.map(\.id) == [second.id])
    }

    @Test("A manifest without month falls back to the creation moment in the current zone, and isn't damaged (L28)")
    func missingMonth() {
        // No `month`: as from a manifest without the key.
        let records = [
            moment(10, 31), moment(10, 31, hour: 23, minute: 30), moment(11, 1, hour: 8), moment(11, 1, hour: 20),
        ]
        .map { BackupRecord(kind: .automatic, createdAt: $0) }
        func prune(in zone: TimeZone) -> [UUID] {
            BackupPolicy.automaticBackupsToPrune(
                in: records,
                retention: BackupRetention(recentAutomatic: 1, monthlyMonths: 12),
                now: moment(11, 1, hour: 21),
                timeZone: zone,
            )
            .map(\.id)
        }
        // In Kolkata 08:00 on 1 Nov is November's keeper; in Los Angeles it's still 31 Oct, so it goes.
        #expect(prune(in: kolkata) == [records[1].id])
        #expect(prune(in: losAngeles) == [records[1].id, records[2].id])
        #expect(records.allSatisfy { $0.isRestorable })
    }

    @Test("A damaged 9 Oct doesn't count toward N; only 2 Oct goes, and 9 Oct stays (L30)")
    func damagedDoesNotCount() {
        var records = (1...10).map { automatic(moment(10, $0)) }
        records[8].condition = .damaged
        let pruned = BackupPolicy.automaticBackupsToPrune(
            in: records,
            retention: .default,
            now: moment(10, 10, hour: 11),
            timeZone: kolkata,
        )
        #expect(pruned.map(\.id) == [records[1].id])
    }

    @Test("A damaged 1 Nov is never November's keeper, and isn't deleted (L31)")
    func damagedIsNeverAKeeper() {
        let november = [automatic(moment(11, 1), .damaged), automatic(moment(11, 2)), automatic(moment(11, 3))]
        let recent = (10...16).map { automatic(moment(11, $0)) }
        let pruned = BackupPolicy.automaticBackupsToPrune(
            in: november + recent,
            retention: .default,
            now: moment(11, 16, hour: 11),
            timeZone: kolkata,
        )
        #expect(pruned.map(\.id) == [november[2].id])
    }

    @Test("Old damaged backups are never deleted or counted, even at N = 1 and M off (L32)")
    func oldDamaged() {
        let damaged = (1...3).map { automatic(moment(1, $0, year: 2025), .damaged) }
        let good = (1...3).map { automatic(moment(10, $0)) }
        let pruned = BackupPolicy.automaticBackupsToPrune(
            in: damaged + good,
            retention: BackupRetention(recentAutomatic: 1, monthlyMonths: 0),
            now: moment(10, 3, hour: 11),
            timeZone: kolkata,
        )
        #expect(pruned.map(\.id) == good.prefix(2).map(\.id))
    }

    @Test("With 2–8 Oct damaged, N = 1 and M off, nothing is deleted (L33)")
    func onlyRestorable() {
        let records = [automatic(moment(10, 1))] + (2...8).map { automatic(moment(10, $0), .damaged) }
        let pruned = BackupPolicy.automaticBackupsToPrune(
            in: records,
            retention: BackupRetention(recentAutomatic: 1, monthlyMonths: 0),
            now: moment(10, 8, hour: 11),
            timeZone: kolkata,
        )
        #expect(pruned.isEmpty)
    }

    @Test("Newer-format folders are never deleted, counted or a keeper, and aren't restorable (L36, L43)")
    func newerFormat() {
        let september = automatic(moment(9, 30), .newerFormat)
        let ancient = automatic(moment(1, 5, year: 2025), .newerFormat)
        let october = (1...10).map { automatic(moment(10, $0)) }
        for retention in [BackupRetention.default, BackupRetention(recentAutomatic: 1, monthlyMonths: 12)] {
            let pruned = BackupPolicy.automaticBackupsToPrune(
                in: [ancient, september] + october,
                retention: retention,
                now: moment(10, 10, hour: 11),
                timeZone: kolkata,
            )
            #expect(!pruned.contains(september))
            #expect(!pruned.contains(ancient))
            // 1 Oct is October's keeper; September has none, since its only backup is of a newer format.
            let expected = retention.recentAutomatic == 1 ? october[1...8] : october[1...2]
            #expect(pruned.map(\.id) == expected.map(\.id))
        }
        let onlyOne = automatic(moment(10, 5))
        let damaged = automatic(moment(10, 6), .damaged)
        #expect(BackupPolicy.keepingARestorableBackup([onlyOne], of: [onlyOne, september, damaged]).isEmpty)
    }

    @Test("A damaged or newer-format backup isn't the day's automatic backup")
    func damagedTodayStillBacksUp() {
        let today = moment(10, 22, hour: 9)
        let catalog = BackupCatalog(records: [
            BackupRecord(kind: .automatic, createdAt: today, fingerprint: "now", condition: .damaged)
        ])
        #expect(!BackupPolicy.hasAutomaticBackup(on: today + 60, timeZone: kolkata, in: catalog))
        #expect(
            BackupPolicy.needsAutomaticBackup(
                now: today + 60,
                timeZone: kolkata,
                catalog: catalog,
                currentFingerprint: "now",
                ledgerIsEmpty: false,
            )
        )
    }
}

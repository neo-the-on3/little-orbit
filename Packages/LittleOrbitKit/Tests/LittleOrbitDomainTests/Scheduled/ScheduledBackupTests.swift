import Foundation
import LittleOrbitDomain
import Testing

/// Backups carry scheduled items in format 1 (#26, D294), and restore checks them first.
@Suite("Scheduled items in backups (#26)")
struct ScheduledBackupTests {
    private typealias Fix = ScheduledFixture

    private func manifest(_ ledger: LedgerSnapshot) -> BackupManifest {
        BackupManifest(
            kind: .manual,
            createdAt: Fix.created,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: ledger.accounts.count,
            transactionCount: ledger.transactions.count,
            attachmentCount: 0,
        )
    }

    private func ledgerWithRent() throws -> LedgerSnapshot {
        var ledger = try LedgerBook.savingScheduledItem(
            Fix.rent(),
            in: Fix.ledger,
            today: Fix.day(2026, 7, 1),
            now: Fix.created,
        )
        ledger =
            LedgerBook.catchingUpScheduledItems(in: ledger, today: Fix.day(2026, 10, 20), now: Fix.created).snapshot
        return ledger
    }

    @Test("Scheduled items and their settled occurrences round-trip, and the manifest lists the section")
    func roundTrip() throws {
        let ledger = try ledgerWithRent()
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let contents = BackupContents(manifest: manifest(ledger), ledger: ledger)
        #expect(contents.manifest.sections.contains(.scheduledItems))
        let decoded = try codec.decode(try codec.encode(contents))
        #expect(BackupContents.canonical(decoded.ledger) == BackupContents.canonical(ledger))
        #expect(decoded.ledger.scheduledItems.first?.occurrences.count == 3)
        // Restored, the settled occurrences still stop a second posting.
        let again = LedgerBook.catchingUpScheduledItems(
            in: decoded.ledger,
            today: Fix.day(2026, 10, 20),
            now: Fix.created,
        )
        #expect(again.result.posted.isEmpty)
    }

    @Test("A pending day kept after an edit round-trips and stays overdue after a restore (D336.1)")
    func pendingRoundTrip() throws {
        var rent = Fix.rent(automatic: false)
        var ledger = try LedgerBook.savingScheduledItem(
            rent,
            in: Fix.ledger,
            today: Fix.day(2026, 7, 1),
            now: Fix.created,
        )
        rent.startDay = Fix.day(2026, 8, 5)
        ledger = try LedgerBook.savingScheduledItem(rent, in: ledger, today: Fix.day(2026, 10, 20), now: Fix.created)
        #expect(ledger.scheduledItems[0].occurrences.map(\.outcome) == [.pending, .pending, .pending])
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let decoded = try codec.decode(try codec.encode(BackupContents(manifest: manifest(ledger), ledger: ledger)))
        #expect(decoded.ledger.scheduledItems == ledger.scheduledItems)
        let board = ScheduledBoard.make(decoded.ledger, today: Fix.day(2026, 10, 20))
        #expect(board.overdue.map(\.day) == [Fix.day(2026, 8, 1), Fix.day(2026, 9, 1), Fix.day(2026, 10, 1)])
    }

    @Test("An occurrence's own values round-trip, and a restored ledger still records it once (D45)")
    func occurrenceEditRoundTrip() throws {
        let rent = Fix.rent(automatic: false)
        var ledger = try LedgerBook.savingScheduledItem(
            rent,
            in: Fix.ledger,
            today: Fix.day(2026, 7, 1),
            now: Fix.created,
        )
        var edited = rent
        edited.amount = 26_000
        edited.note = nil
        ledger = try LedgerBook.savingScheduledOccurrence(
            edited,
            editing: ScheduledOccurrenceSave(
                occurrence: Fix.day(2026, 12, 1),
                dueDay: Fix.day(2026, 12, 3),
                scope: .thisOccurrence,
            ),
            in: ledger,
            today: Fix.day(2026, 11, 20),
            now: Fix.created,
        )
        let record = try #require(ledger.scheduledItems.first?.occurrence(on: Fix.day(2026, 12, 1)))
        #expect(record.outcome == .edited)
        #expect(record.edit?.fields == [.day, .amount])
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let decoded = try codec.decode(try codec.encode(BackupContents(manifest: manifest(ledger), ledger: ledger)))
        #expect(decoded.ledger.scheduledItems == ledger.scheduledItems)
        let board = ScheduledBoard.make(decoded.ledger, today: Fix.day(2026, 12, 3))
        #expect(board.dueToday.map(\.key) == [Fix.day(2026, 12, 1)])
        #expect(board.dueToday.map(\.occurrenceItem.amount) == [26_000])
    }

    @Test("A ledger without scheduled items encodes as before: no section and no scheduled key")
    func unchangedWithout() throws {
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let ledger = Fix.ledger
        let contents = BackupContents(manifest: manifest(ledger), ledger: ledger)
        #expect(!contents.manifest.sections.contains(.scheduledItems))
        let json = try #require(String(bytes: try JSONEncoder().encode(ledger), encoding: .utf8))
        #expect(!json.contains("scheduledItems"))
        let decoded = try codec.decode(try codec.encode(contents))
        #expect(decoded.ledger.scheduledItems.isEmpty)
    }

    @Test("A backup that settles one occurrence twice is damaged")
    func duplicateOccurrenceIsDamage() throws {
        var ledger = try ledgerWithRent()
        let first = try #require(ledger.scheduledItems[0].occurrences.first)
        ledger.scheduledItems[0].occurrences.append(first)
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let files = try codec.encode(BackupContents(manifest: manifest(ledger), ledger: ledger))
        #expect(throws: BackupError.damaged) {
            try codec.decode(files)
        }
    }

    @Test("#174 rebase: budgets and scheduled items share one format 1 backup, each in its own section")
    func besideBudgets() throws {
        var ledger = try ledgerWithRent()
        let budget = Budget(
            name: "Household",
            currencyCode: "INR",
            categoryIDs: [],
            startDay: Fix.day(2026, 7, 1),
            recurrence: .monthly,
            limit: 30_000,
            createdAt: Fix.created,
        )
        ledger.budgets = [budget]
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let contents = BackupContents(manifest: manifest(ledger), ledger: ledger)
        #expect(contents.manifest.formatVersion == 1)
        #expect(contents.manifest.sections == BackupSection.populated + [.budgets, .scheduledItems])
        let decoded = try codec.decode(try codec.encode(contents))
        #expect(BackupContents.canonical(decoded.ledger) == BackupContents.canonical(ledger))
        #expect(decoded.ledger.budgets == [budget])
        #expect(decoded.ledger.scheduledItems.first?.occurrences.count == 3)
        var budgetsOnly = ledger
        budgetsOnly.scheduledItems = []
        #expect(try codec.fingerprint(of: ledger) != codec.fingerprint(of: budgetsOnly))
    }
}

/// D354.1: whether the app recorded an occurrence travels in format 1, and older backups read it as unset.
@Suite("Scheduled occurrences recorded automatically, in backups (#26, D354.1)")
struct ScheduledAutoRecordBackupTests {
    private typealias Fix = ScheduledFixture

    @Test("Catch-up marks what it records; the user's Pay doesn't")
    func catchUpMarks() throws {
        var ledger = try LedgerBook.savingScheduledItem(
            Fix.rent(automatic: true),
            in: Fix.ledger,
            today: Fix.day(2026, 7, 1),
            now: Fix.created,
        )
        ledger =
            LedgerBook.catchingUpScheduledItems(in: ledger, today: Fix.day(2026, 9, 30), now: Fix.created)
            .snapshot
        let item = ledger.scheduledItems[0]
        #expect(!item.occurrences.isEmpty)
        #expect(item.occurrences.allSatisfy { $0.recordedAutomatically == true })
        let next = try #require(
            ScheduleCalendar.firstOccurrence(of: item, onOrAfter: Fix.day(2026, 10, 1), where: { _ in true })
        )
        let paid = try LedgerBook.settlingScheduledOccurrence(
            .pay(itemID: item.id, occurrence: next, postedOn: Fix.day(2026, 9, 30)),
            in: ledger,
            now: Fix.created,
        )
        #expect(paid.snapshot.scheduledItems[0].occurrence(on: next)?.recordedAutomatically == nil)
    }

    @Test("The flag round-trips in a format 1 backup")
    func roundTrip() throws {
        var ledger = try LedgerBook.savingScheduledItem(
            Fix.rent(automatic: true),
            in: Fix.ledger,
            today: Fix.day(2026, 7, 1),
            now: Fix.created,
        )
        ledger =
            LedgerBook.catchingUpScheduledItems(in: ledger, today: Fix.day(2026, 9, 30), now: Fix.created)
            .snapshot
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: Fix.created,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: ledger.accounts.count,
            transactionCount: ledger.transactions.count,
            attachmentCount: 0,
        )
        let decoded = try codec.decode(try codec.encode(BackupContents(manifest: manifest, ledger: ledger)))
        #expect(decoded.ledger.scheduledItems[0].occurrences.allSatisfy { $0.recordedAutomatically == true })
    }

    @Test("A restore keeps the flag only on a posted occurrence, and reads false as unset")
    func restoreNormalises() throws {
        var ledger = try LedgerBook.savingScheduledItem(
            Fix.rent(automatic: true),
            in: Fix.ledger,
            today: Fix.day(2026, 7, 1),
            now: Fix.created,
        )
        let item = ledger.scheduledItems[0]
        func occurrence(_ month: Int, _ outcome: ScheduledOutcome, _ flag: Bool?) -> ScheduledOccurrence {
            let day = Fix.day(2026, month, 1)
            var occurrence = ScheduledOccurrence(
                id: ScheduledKey.occurrenceID(item: item.id, day: day),
                day: day,
                outcome: outcome,
                transactionID: outcome == .posted ? UUID() : nil,
                createdAt: Fix.created,
            )
            occurrence.recordedAutomatically = flag
            return occurrence
        }
        let written = [
            occurrence(7, .posted, true), occurrence(8, .posted, false), occurrence(9, .skipped, true),
            occurrence(10, .pending, true), occurrence(11, .skipped, false),
        ]
        ledger.scheduledItems[0].occurrences = written
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: Fix.created,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: ledger.accounts.count,
            transactionCount: ledger.transactions.count,
            attachmentCount: 0,
        )
        let decoded = try codec.decode(try codec.encode(BackupContents(manifest: manifest, ledger: ledger)))
        let read = decoded.ledger.scheduledItems[0].occurrences.sorted { $0.day < $1.day }
        #expect(read.count == written.count)
        #expect(read.map(\.recordedAutomatically) == [true, nil, nil, nil, nil])
        #expect(read.map(\.outcome) == written.map(\.outcome))
        #expect(read.map(\.id) == written.map(\.id))
        // The same rule when an occurrence is made directly, as the store's mapping does.
        let skipped = ScheduledOccurrence(
            id: UUID(),
            day: Fix.day(2026, 9, 1),
            outcome: .skipped,
            recordedAutomatically: true,
            createdAt: Fix.created,
        )
        #expect(skipped.recordedAutomatically == nil)
    }

    @Test("An occurrence from a backup made before the flag reads it as unset")
    func olderBackupReadsUnset() throws {
        let occurrence = ScheduledOccurrence(
            id: UUID(),
            day: Fix.day(2026, 9, 1),
            outcome: .posted,
            transactionID: UUID(),
            recordedAutomatically: true,
            createdAt: Fix.created,
        )
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(occurrence)) as? [String: Any]
        )
        #expect(object["recordedAutomatically"] as? Bool == true)
        object["recordedAutomatically"] = nil
        let older = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ScheduledOccurrence.self, from: older)
        #expect(decoded.recordedAutomatically == nil)
        #expect(decoded.outcome == .posted)
        // A user's Pay is written without the key, as before.
        var userPaid = occurrence
        userPaid.recordedAutomatically = nil
        let written = try #require(String(bytes: try JSONEncoder().encode(userPaid), encoding: .utf8))
        #expect(!written.contains("recordedAutomatically"))
    }
}

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

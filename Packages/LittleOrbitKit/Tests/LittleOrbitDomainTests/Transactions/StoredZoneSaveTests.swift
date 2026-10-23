import Foundation
import LittleOrbitDomain
import Testing

/// An edit keeps a record's stored zone ID, even one this device doesn't recognise (D230, #131 comment 6364099876).
@Suite("Saving an edit keeps the stored zone ID")
struct StoredZoneSaveTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private func snapshot(with transaction: Transaction) -> LedgerSnapshot {
        LedgerSnapshot(accounts: F.accounts, transactions: [transaction])
    }

    @Test("An edit that keeps an unrecognised zone ID saves, and the ID is unchanged", arguments: ["Not/AZone", ""])
    func keepsUnknownZone(zoneID: String) throws {
        var restored = F.expense(500, on: F.date(2026, 10, 10, 21, zone: "UTC"))
        restored.timeZoneID = zoneID
        var edited = restored
        edited.date = F.date(2026, 10, 12, 21, zone: "UTC")
        let saved = try LedgerBook.savingTransaction(edited, in: snapshot(with: restored), now: F.date(2026, 10, 20))
        #expect(saved.transactions.first?.timeZoneID == zoneID)
        #expect(saved.transactions.first?.date == edited.date)
    }

    @Test("An unrecognised zone ID is still refused on a new record, or when an edit changes it")
    func refusesNewUnknownZone() {
        var new = F.expense(500, on: F.date(2026, 10, 10))
        new.timeZoneID = "Not/AZone"
        #expect(throws: LedgerValidationError.invalidTimeZone) {
            try LedgerBook.savingTransaction(new, in: LedgerSnapshot(accounts: F.accounts), now: F.date(2026, 10, 20))
        }
        let stored = F.expense(500, on: F.date(2026, 10, 10))
        var changed = stored
        changed.timeZoneID = "Not/AZone"
        #expect(throws: LedgerValidationError.invalidTimeZone) {
            try LedgerBook.savingTransaction(changed, in: snapshot(with: stored), now: F.date(2026, 10, 20))
        }
    }
}

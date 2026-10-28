import Foundation
import LittleOrbitDomain
import Testing

/// #207 B1: the received amount's currency is an optional field. Backup format 1 carries it, and an item from
/// before it existed reads with none.
@Suite("The received amount's currency in backups (#207 B1)")
struct ScheduledReceivedCurrencyBackupTests {
    private typealias Fix = ScheduledFixture

    private func share(code: String?) -> ScheduledItem {
        ScheduledItem(
            type: .transfer,
            amount: 1_000,
            destinationAmount: 12,
            receivedCurrencyCode: code,
            accountID: Fix.savingsID,
            transferAccountID: UUID(),
            details: "Rent Share",
            startDay: Fix.day(2026, 11, 1),
            timeZoneID: "Asia/Kolkata",
            createdAt: Fix.created,
        )
    }

    @Test("Backup format stays 1, and an item round-trips with its received currency")
    func roundTrip() throws {
        #expect(BackupFormat.currentVersion == 1)
        var ledger = Fix.ledger
        ledger.scheduledItems = [share(code: "USD")]
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: Fix.created,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: ledger.accounts.count,
            transactionCount: 0,
            attachmentCount: 0,
        )
        let decoded = try codec.decode(try codec.encode(BackupContents(manifest: manifest, ledger: ledger)))
        #expect(decoded.ledger.scheduledItems.first?.receivedCurrencyCode == "USD")
    }

    @Test("An item saved before the field existed decodes, with no received currency")
    func oldShapeDecodes() throws {
        let encoded = try JSONEncoder().encode(share(code: "USD"))
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["receivedCurrencyCode"] as? String == "USD")
        object.removeValue(forKey: "receivedCurrencyCode")
        let old = try JSONDecoder()
            .decode(ScheduledItem.self, from: try JSONSerialization.data(withJSONObject: object))
        #expect(old.receivedCurrencyCode == nil)
        #expect(old.destinationAmount == 12)
    }
}

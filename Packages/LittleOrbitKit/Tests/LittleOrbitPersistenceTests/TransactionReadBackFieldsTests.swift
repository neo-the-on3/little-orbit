import Foundation
import LittleOrbitDomain
import Testing

/// N5 on #286: the incremental write reads back only the fields a write changed
/// (`TransactionRecord.readBack`, macOS and iOS only). It lists every field of `Transaction` but `id`; a new
/// field must be added there too, or the stored ledger would keep its old value after a write changes it.
@Suite("Transaction read-back covers every field")
struct TransactionReadBackFieldsTests {
    @Test("Transaction has exactly the fields readBack compares")
    func fields() {
        let transaction = Transaction(type: .expense, amount: 1, date: .now, timeZoneID: "UTC", accountID: UUID())
        let names = Mirror(reflecting: transaction).children.compactMap(\.label)
        #expect(
            names == [
                "id", "type", "amount", "date", "timeZoneID", "accountID", "categoryID", "payeeID", "details", "note",
                "transferAccountID", "destinationAmount", "scheduledTemplateID", "scheduledOccurrenceDate", "status",
                "tagIDs", "refundOfID", "isRefund", "createdAt", "updatedAt", "deletedAt",
            ]
        )
    }
}

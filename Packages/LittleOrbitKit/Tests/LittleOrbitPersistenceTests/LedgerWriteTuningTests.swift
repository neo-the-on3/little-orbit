import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// #265: which path a write takes by its size. Plain values, so it runs on every platform; the thresholds
/// themselves come from Tester2's Mac timing ladder (comment 6429140787).
@Suite("Large-write tuning (#265)")
struct LedgerWriteTuningTests {
    @Test("A write deletes one by one below the threshold and on the large-delete path from it")
    func deletePath() {
        let threshold = LedgerWriteTuning.largeDeleteThreshold
        #expect(LedgerWriteTuning.deletePath(forDeleting: 0) == .oneByOne)
        #expect(LedgerWriteTuning.deletePath(forDeleting: threshold - 1) == .oneByOne)
        #expect(LedgerWriteTuning.deletePath(forDeleting: threshold) == .unlinkFirst)
        #expect(LedgerWriteTuning.deletePath(forDeleting: 5000) == .unlinkFirst)
        #expect(threshold == 20)
    }

    @Test("Written transactions are linked from their parents from the link threshold")
    func linkPath() {
        let threshold = LedgerWriteTuning.largeLinkThreshold
        #expect(!LedgerWriteTuning.linksFromParents(forLinking: 1))
        #expect(!LedgerWriteTuning.linksFromParents(forLinking: threshold - 1))
        #expect(LedgerWriteTuning.linksFromParents(forLinking: threshold))
        #expect(threshold == 100)
    }

    @Test("Undo Import of a batch counts every record it deletes")
    func deletedCount() {
        let account = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
        let payees = (0..<3).map { Payee(name: "Kiosk \($0)") }
        let imported = (0..<5)
            .map { index in
                Transaction(
                    amount: Decimal(index + 1),
                    timeZoneID: "UTC",
                    accountID: account.id,
                    payeeID: payees[index % 3].id,
                )
            }
        let kept = Transaction(amount: 9, timeZoneID: "UTC", accountID: account.id)
        let base = LedgerSnapshot(accounts: [account], transactions: imported + [kept], payees: payees)
        let target = LedgerSnapshot(accounts: [account], transactions: [kept])
        let changes = LedgerWriteSet(from: base, to: target)
        #expect(changes.deletedCount == 8)
        #expect(changes.wholeStoreReason == nil)
        #expect(LedgerWriteSet(from: base, to: base).deletedCount == 0)
    }
}

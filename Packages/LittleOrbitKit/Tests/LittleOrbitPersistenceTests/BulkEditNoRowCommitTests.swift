import Foundation
import Testing

@testable import LittleOrbitDomain
@testable import LittleOrbitPersistence

/// N5 on #286: an Apply that changes no row gets no Undo step, so its commit writes nothing at all, not even a
/// payee the edit typed, which nothing would remove.
@MainActor
@Suite("Bulk edit: a commit that changes no row")
struct BulkEditNoRowCommitTests {
    @Test("A typed payee with no row changed: nothing written, an empty change")
    func payeeOnly() throws {
        let repository = InMemoryLedgerRepository()
        try repository.replaceLedger(with: BulkEditUseCaseTiming.ledger())
        let base = try repository.batchBase()
        var snapshot = base.snapshot
        let payee = try #require(
            try DefaultSaveTransactionsUseCase.resolvePayee(
                named: "New Shop",
                createdAt: base.now,
                in: &snapshot,
                now: base.now,
            )
        )
        #expect(payee.isNew)
        let changeSet = BulkEditChangeSet(
            result: LedgerBatchResult(snapshot: snapshot, previous: []),
            created: [payee.payee],
            changesNoRow: true,
            revision: base.revision,
        )
        let request = try BulkEditUseCaseTiming.request(in: repository)
        let change = try DefaultApplyBulkEditUseCase(repository: repository).commit(changeSet, for: request)
        #expect(change == .replaced([]))
        #expect(change.changesNoTransaction)
        #expect(try repository.batchBase().snapshot == base.snapshot)
        #expect(try repository.batchBase().revision == base.revision)
        #expect(!TransactionChange.saved(.replaced([]), creating: [payee.payee]).changesNoTransaction)
    }
}

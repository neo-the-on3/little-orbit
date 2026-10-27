import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

/// #285, B (Tech Architect's review 5667872455, m1): the stale checks around a batch's hand-off to a background
/// save, each tested directly. The store's own revision guard in `writeBatchOffMain`; the rebuild when the store
/// moved before the hand-off, for an Undo; the rebuild when it moved at the hand-off, for Apply and Undo; and
/// `LedgerBatchStale` once every attempt found it moved. Made-up data.
@MainActor
@Suite("Batch hand-off stale checks (#285, B)")
struct OffMainHandOffTests {
    typealias Ledger = OffMainBatchCommitTests.Ledger
    typealias Calls = OffMainBatchCommitTests.Calls

    /// The Bulk Edit of every row, applied, and what reverting it expects.
    private static func applied(_ ledger: Ledger) async throws -> (TransactionChange, ChangeOutcome) {
        let change = try await DefaultApplyBulkEditUseCase(repository: ledger.repository)
            .apply(ledger.request(), reporting: .silent)
        let outcome = try DefaultTransactionChangesUseCase(repository: ledger.repository).outcome(of: change)
        return (change, outcome)
    }

    private static func renamed(_ ledger: Ledger) throws -> Transaction {
        var renamed = try #require(try ledger.repository.transactions().first { $0.id == ledger.rows[1].id })
        renamed.details = "StreamBox Annual"
        return renamed
    }

    @Test("The store's guard: a stale expected revision writes nothing and returns false")
    func staleExpectedRevision() async throws {
        let ledger = try Ledger(offMain: true)
        var saves = 0
        ledger.repository.offMainSave = { saves += 1 }
        let other = try Ledger(offMain: false)
        try other.repository.saveTransaction(try Self.renamed(other))
        let target = try other.repository.ledgerSnapshot()
        let revision = try #require(ledger.repository.revision)
        let before = try ledger.repository.transactions()

        #expect(try await !ledger.repository.writeBatchOffMain(target, expectedRevision: revision &- 1))
        #expect(saves == 0, "Nothing handed off")
        #expect(ledger.repository.revision == revision)
        #expect(try ledger.repository.transactions() == before)

        #expect(try await ledger.repository.writeBatchOffMain(target, expectedRevision: revision))
        #expect(saves == 1)
        #expect(try ledger.repository.transactions() == other.repository.transactions())
    }

    @Test("Undo: the store moved just before the hand-off, so it's built again from the store as it is then")
    func undoRebuiltWhenStoreMoved() async throws {
        let ledger = try Ledger(offMain: true)
        let (change, outcome) = try await Self.applied(ledger)
        let renamed = try Self.renamed(ledger)
        let calls = Calls()
        let result = try await DefaultTransactionChangesUseCase(repository: ledger.repository)
            .revert(
                change,
                expecting: outcome,
                reporting: ledger.reporter(calls) { try? ledger.repository.saveTransaction(renamed) },
            )
        guard case .reverted(let inverse, _) = result else {
            Issue.record("Expected a revert, got \(result)")
            return
        }
        let stored = try ledger.repository.transactions()
        #expect(stored.allSatisfy { $0.categoryID == nil }, "Reverted")
        #expect(stored.first { $0.id == renamed.id }?.details == "StreamBox Annual", "The other write stays")
        guard case .replaced(let previous) = inverse.core else {
            Issue.record("Expected an edit, got \(inverse)")
            return
        }
        #expect(previous.first { $0.id == renamed.id }?.details == "StreamBox Annual", "Redo keeps it too")
    }

    @Test("Undo: the store moved under the step just before the hand-off: stale, and nothing more is written")
    func undoStaleWhenStepMoved() async throws {
        let ledger = try Ledger(offMain: true)
        let (change, outcome) = try await Self.applied(ledger)
        var moved = try #require(try ledger.repository.transactions().first { $0.id == ledger.rows[0].id })
        moved.categoryID = nil
        let result = try await DefaultTransactionChangesUseCase(repository: ledger.repository)
            .revert(
                change,
                expecting: outcome,
                reporting: ledger.reporter(Calls()) { try? ledger.repository.saveTransaction(moved) },
            )
        guard case .stale = result else {
            Issue.record("Expected stale, got \(result)")
            return
        }
        let stored = try ledger.repository.transactions()
        #expect(stored.filter { $0.id != moved.id }.allSatisfy { $0.categoryID == ledger.groceries.id })
    }

    @Test("Apply: the store moved at the hand-off, so it's built again and handed off once more")
    func applyRebuiltAtHandOff() async throws {
        let ledger = try Ledger(offMain: true)
        let renamed = try Self.renamed(ledger)
        let store = HandOffMovingRepository(ledger.repository, moves: 1)
        store.move = { try $0.saveTransaction(renamed) }
        _ = try await DefaultApplyBulkEditUseCase(repository: store).apply(ledger.request(), reporting: .silent)
        #expect(store.handOffs == 2)
        let stored = try ledger.repository.transactions()
        #expect(stored.allSatisfy { $0.categoryID == ledger.groceries.id })
        #expect(stored.first { $0.id == renamed.id }?.details == "StreamBox Annual", "The other write stays")
    }

    @Test("Undo: the store moved at the hand-off, so it's checked, built again and handed off once more")
    func undoRebuiltAtHandOff() async throws {
        let ledger = try Ledger(offMain: true)
        let (change, outcome) = try await Self.applied(ledger)
        let renamed = try Self.renamed(ledger)
        let store = HandOffMovingRepository(ledger.repository, moves: 1)
        store.move = { try $0.saveTransaction(renamed) }
        let result = try await DefaultTransactionChangesUseCase(repository: store)
            .revert(change, expecting: outcome, reporting: .silent)
        guard case .reverted = result else {
            Issue.record("Expected a revert, got \(result)")
            return
        }
        #expect(store.handOffs == 2)
        let stored = try ledger.repository.transactions()
        #expect(stored.allSatisfy { $0.categoryID == nil })
        #expect(stored.first { $0.id == renamed.id }?.details == "StreamBox Annual", "The other write stays")
    }

    @Test("Apply: LedgerBatchStale once every hand-off found the store moved; the batch wrote nothing")
    func applyStaleAfterAttempts() async throws {
        let ledger = try Ledger(offMain: true)
        let store = HandOffMovingRepository(ledger.repository, moves: .max)
        await #expect(throws: LedgerBatchStale.self) {
            _ = try await DefaultApplyBulkEditUseCase(repository: store).apply(ledger.request(), reporting: .silent)
        }
        #expect(store.handOffs == 3, "LedgerBatchBase.handOffAttempts")
        #expect(try ledger.repository.transactions() == ledger.rows)
    }

    @Test("Undo: LedgerBatchStale once every hand-off found the store moved; the revert wrote nothing")
    func undoStaleAfterAttempts() async throws {
        let ledger = try Ledger(offMain: true)
        let (change, outcome) = try await Self.applied(ledger)
        let edited = try ledger.repository.transactions()
        let store = HandOffMovingRepository(ledger.repository, moves: .max)
        await #expect(throws: LedgerBatchStale.self) {
            _ = try await DefaultTransactionChangesUseCase(repository: store)
                .revert(change, expecting: outcome, reporting: .silent)
        }
        #expect(store.handOffs == 3, "LedgerBatchBase.handOffAttempts")
        #expect(try ledger.repository.transactions() == edited)
    }
}

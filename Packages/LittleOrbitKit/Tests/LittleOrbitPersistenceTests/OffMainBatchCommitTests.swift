import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

/// #285, B: a Bulk Edit Apply and its Undo through a store that saves off the main actor, here the in-memory store
/// with its `offMainSave` stand-in. The revision check and any rebuild stay on the main actor right before the
/// hand-off, and the result is the one the main-actor commit gives. Made-up data.
@MainActor
@Suite("Batch commit with the save off the main actor (#285, B)")
struct OffMainBatchCommitTests {
    static let day = Date(timeIntervalSince1970: 1_792_400_000)

    /// Which of the reporter's "about to save" calls ran.
    final class Calls {
        var values: [String] = []
    }

    /// The same made-up ledger for each store, so the two can be compared value for value.
    static let savings = Account(name: "Everyday Savings", currencyCode: "INR")
    static let groceries = TransactionCategory(name: "Groceries", kind: .expense)
    static let seed = [("450", "Corner Bakery"), ("649", "StreamBox"), ("200", "Metro Card")]
        .map { amount, details in
            Transaction(
                type: .expense,
                amount: Decimal(string: amount) ?? 0,
                date: day,
                timeZoneID: "Asia/Kolkata",
                accountID: savings.id,
                details: details,
            )
        }

    @MainActor
    struct Ledger {
        let repository: InMemoryLedgerRepository
        let savings = OffMainBatchCommitTests.savings
        let groceries = OffMainBatchCommitTests.groceries
        let rows: [Transaction]

        init(offMain: Bool) throws {
            repository = InMemoryLedgerRepository(now: { OffMainBatchCommitTests.day }, seedPending: false)
            try repository.saveAccount(savings)
            try repository.saveCategory(groceries)
            for transaction in OffMainBatchCommitTests.seed {
                try repository.saveTransaction(transaction)
            }
            rows = try repository.transactions()
            if offMain {
                repository.offMainSave = {}
            }
        }

        func request(_ selection: [Transaction]? = nil) -> BulkEditRequest {
            var changes = BulkEditChanges()
            changes.categoryID = .some(groceries.id)
            return BulkEditRequest(
                selection: selection ?? rows,
                changes: changes,
                payeeName: "",
                accounts: [savings],
                timeZoneID: "Asia/Kolkata",
                now: OffMainBatchCommitTests.day,
            )
        }

        func reporter(_ calls: Calls, willSave: @escaping @MainActor () -> Void = {}) -> LedgerBatchReporter {
            LedgerBatchReporter(
                willSave: { _ in calls.values.append("willSave") },
                willSaveOffMain: { rows in
                    calls.values.append("willSaveOffMain \(rows)")
                    willSave()
                },
            )
        }
    }

    @Test("Apply: the off-main report, then one write, the same as the main-actor commit")
    func applyMatchesMainActor() async throws {
        let onMain = try Ledger(offMain: false)
        let offMain = try Ledger(offMain: true)
        let calls = Calls()
        let expected = try await DefaultApplyBulkEditUseCase(repository: onMain.repository)
            .apply(onMain.request(), reporting: onMain.reporter(Calls()))
        let before = try #require(offMain.repository.revision)
        let change = try await DefaultApplyBulkEditUseCase(repository: offMain.repository)
            .apply(offMain.request(), reporting: offMain.reporter(calls))
        #expect(calls.values == ["willSaveOffMain 3"])
        #expect(change == expected)
        #expect(offMain.repository.revision == before + 1, "One write")
        #expect(try offMain.repository.transactions() == onMain.repository.transactions())
    }

    @Test("Apply: the store moved just before the hand-off, so it's built again from the store as it is then")
    func applyRebuiltWhenStoreMoved() async throws {
        let ledger = try Ledger(offMain: true)
        let calls = Calls()
        var renamed = ledger.rows[1]
        renamed.details = "StreamBox Annual"
        let change = try await DefaultApplyBulkEditUseCase(repository: ledger.repository)
            .apply(
                ledger.request(),
                reporting: ledger.reporter(calls) { try? ledger.repository.saveTransaction(renamed) },
            )
        let stored = try ledger.repository.transactions()
        #expect(stored.allSatisfy { $0.categoryID == ledger.groceries.id })
        #expect(stored.first { $0.id == renamed.id }?.details == "StreamBox Annual", "The other write stays")
        guard case .replaced(let previous) = change.core else {
            Issue.record("Expected an edit, got \(change)")
            return
        }
        #expect(
            previous.first { $0.id == renamed.id }?.details == "StreamBox Annual",
            "Undo restores the store as it was",
        )
    }

    @Test("A failed save off the main actor writes nothing and throws")
    func failedSave() async throws {
        let ledger = try Ledger(offMain: true)
        struct SaveFailed: Error {}
        ledger.repository.offMainSave = { throw SaveFailed() }
        await #expect(throws: SaveFailed.self) {
            _ = try await DefaultApplyBulkEditUseCase(repository: ledger.repository)
                .apply(ledger.request(), reporting: ledger.reporter(Calls()))
        }
        #expect(try ledger.repository.transactions() == ledger.rows)
    }

    @Test("Undo: the same inverse and outcome as the main-actor revert, with one write")
    func revertMatchesMainActor() async throws {
        let onMain = try Ledger(offMain: false)
        let offMain = try Ledger(offMain: true)
        func undo(_ ledger: Ledger, _ calls: Calls) async throws -> RevertResult {
            let change = try await DefaultApplyBulkEditUseCase(repository: ledger.repository)
                .apply(ledger.request(), reporting: .silent)
            let changes = DefaultTransactionChangesUseCase(repository: ledger.repository)
            let outcome = try changes.outcome(of: change)
            return try await changes.revert(change, expecting: outcome, reporting: ledger.reporter(calls))
        }
        let expected = try await undo(onMain, Calls())
        let calls = Calls()
        let result = try await undo(offMain, calls)
        #expect(calls.values == ["willSaveOffMain 3"])
        #expect(result == expected)
        #expect(try offMain.repository.transactions() == onMain.repository.transactions())
        #expect(try offMain.repository.transactions().allSatisfy { $0.categoryID == nil })
    }
}

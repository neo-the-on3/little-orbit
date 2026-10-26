import Foundation
import LittleOrbitDomain
import Testing

/// Bulk Edit's Apply (#268, D393): all or nothing when a selected transaction was deleted elsewhere after the sheet
/// opened, say in another window. Made-up data.
@MainActor
@Suite("Bulk edit apply (D393)")
struct BulkEditApplyTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private let rows = [
        F.expense(450, on: F.date(2026, 10, 1)),
        F.expense(649, on: F.date(2026, 10, 2)),
        F.expense(200, on: F.date(2026, 10, 3)),
    ]

    /// Ticks Description and Date, and Payee with a name no payee has yet, so a refused apply could leave a payee.
    private func request(_ selection: [Transaction]) -> BulkEditRequest {
        var changes = BulkEditChanges()
        changes.details = .some("Weekly order")
        changes.date = F.date(2026, 10, 20)
        changes.payeeID = .some(nil)
        return BulkEditRequest(
            selection: selection,
            changes: changes,
            payeeName: "Corner Bakery",
            accounts: F.accounts,
            timeZoneID: F.india,
            now: F.date(2026, 10, 21),
        )
    }

    private func setup() throws -> (FakeLedgerRepository, any ApplyBulkEditUseCase) {
        let repository = try FakeLedgerRepository(accounts: F.accounts, transactions: rows)
        let useCases = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames())
        return (repository, useCases.bulkEdit)
    }

    @Test("One deleted: refused, naming it, and nothing changes on the others; no payee is created (D393.1)")
    func oneDeleted() throws {
        let (repository, bulkEdit) = try setup()
        let selection = try repository.transactions()
        try repository.deleteTransaction(id: rows[1].id)
        let before = repository.snapshot

        #expect(throws: BulkEditSelectionDeleted(ids: [rows[1].id])) {
            try bulkEdit.apply(request(selection))
        }
        #expect(repository.snapshot == before)
        #expect(
            try repository.transactions().map(\.id).sorted { $0.uuidString < $1.uuidString }
                == [
                    rows[0].id, rows[2].id,
                ]
                .sorted { $0.uuidString < $1.uuidString }
        )
        #expect(try repository.payees().isEmpty)
    }

    @Test("Several deleted: refused, naming each, and nothing is recreated (D393.1)")
    func severalDeleted() throws {
        let (repository, bulkEdit) = try setup()
        let selection = try repository.transactions()
        try repository.deleteTransaction(id: rows[0].id)
        try repository.deleteTransaction(id: rows[2].id)
        let before = repository.snapshot

        #expect(throws: BulkEditSelectionDeleted(ids: [rows[0].id, rows[2].id])) {
            try bulkEdit.apply(request(selection))
        }
        #expect(repository.snapshot == before)
        #expect(try repository.transactions().map(\.id) == [rows[1].id])
    }

    @Test("A deleted row the edit wouldn't change still refuses the apply: the whole selection is checked")
    func deletedButUnchanged() throws {
        let (repository, bulkEdit) = try setup()
        var selection = try repository.transactions()
        // The last row already has the description, so the edit alone wouldn't write it.
        selection[2].details = "Weekly order"
        try repository.saveTransaction(selection[2])
        selection = try repository.transactions()
        try repository.deleteTransaction(id: rows[2].id)
        var changes = BulkEditChanges()
        changes.details = .some("Weekly order")
        let before = repository.snapshot

        #expect(throws: BulkEditSelectionDeleted(ids: [rows[2].id])) {
            try bulkEdit.apply(
                BulkEditRequest(
                    selection: selection,
                    changes: changes,
                    payeeName: "",
                    accounts: F.accounts,
                    timeZoneID: F.india,
                    now: F.date(2026, 10, 21),
                )
            )
        }
        #expect(repository.snapshot == before)
    }

    @Test("None deleted: every row changes in one change, with the new payee, for one Undo step")
    func noneDeleted() throws {
        let (repository, bulkEdit) = try setup()
        let selection = try repository.transactions()

        let change = try bulkEdit.apply(request(selection))
        let payee = try #require(try repository.payees().first)
        #expect(payee.name == "Corner Bakery")
        let saved = try repository.transactions()
        #expect(saved.count == 3)
        #expect(saved.allSatisfy { $0.details == "Weekly order" && $0.payeeID == payee.id })
        #expect(saved.allSatisfy { $0.date == F.date(2026, 10, 20) })
        guard case .createdPayees(let created, .replaced(let previous)) = change else {
            Issue.record("Expected one replaced change that created the payee, got \(change)")
            return
        }
        #expect(created.map(\.id) == [payee.id])
        #expect(Set(previous.map(\.id)) == Set(rows.map(\.id)))
    }

    @Test("After a refusal, applying to the rows that are left changes only them (D393.3)")
    func applyAgain() throws {
        let (repository, bulkEdit) = try setup()
        var selection = try repository.transactions()
        try repository.deleteTransaction(id: rows[1].id)
        #expect(throws: BulkEditSelectionDeleted.self) { try bulkEdit.apply(request(selection)) }

        selection.removeAll { $0.id == rows[1].id }
        let change = try bulkEdit.apply(request(selection))
        let saved = try repository.transactions()
        #expect(saved.count == 2)
        #expect(saved.allSatisfy { $0.details == "Weekly order" })
        #expect(!saved.contains { $0.id == rows[1].id })
        #expect(try repository.payees().count == 1)
        if case .createdPayees(_, .replaced(let previous)) = change {
            #expect(Set(previous.map(\.id)) == [rows[0].id, rows[2].id])
        } else {
            Issue.record("Expected a replaced change, got \(change)")
        }
    }

    @Test("A transaction write that fails after the new payee was saved leaves no payee: one store change (D393.1)")
    func failedWriteLeavesNoPayee() throws {
        let (repository, bulkEdit) = try setup()
        let selection = try repository.transactions()
        // `savePayee` isn't a counted write, so the payee is saved and the first transaction write then fails.
        repository.failsAfterWrites = repository.writes
        let before = repository.snapshot

        #expect(throws: FakeLedgerRepository.WriteFailure.self) { try bulkEdit.apply(request(selection)) }
        #expect(repository.snapshot == before)
        #expect(try repository.payees().isEmpty)
        #expect(try repository.transactions().allSatisfy { $0.details != "Weekly order" })
    }

    @Test("Only transfers with a new payee typed: no payee is created, since Payee skips transfers (D114)")
    func transfersOnlyCreatesNoPayee() throws {
        let (repository, bulkEdit) = try setup()
        let transfer = F.transfer(50, on: F.date(2026, 10, 5))
        try repository.saveTransaction(transfer)
        let selection = try repository.transactions().filter { $0.id == transfer.id }
        var changes = BulkEditChanges()
        changes.payeeID = .some(nil)
        let before = repository.snapshot
        let change = try bulkEdit.apply(
            BulkEditRequest(
                selection: selection,
                changes: changes,
                payeeName: "New Shop",
                accounts: F.accounts,
                timeZoneID: F.india,
                now: F.date(2026, 10, 21),
            )
        )
        #expect(change == .replaced([]))
        #expect(try repository.payees().isEmpty)
        #expect(repository.snapshot == before)
    }

    @Test("Nothing to change: an empty change, and nothing written")
    func nothingChanges() throws {
        let (repository, bulkEdit) = try setup()
        let transfer = F.transfer(50, on: F.date(2026, 10, 5))
        try repository.saveTransaction(transfer)
        let selection = try repository.transactions().filter { $0.id == transfer.id }
        var changes = BulkEditChanges()
        changes.categoryID = .some(nil)
        let before = repository.snapshot
        let change = try bulkEdit.apply(
            BulkEditRequest(
                selection: selection,
                changes: changes,
                payeeName: "",
                accounts: F.accounts,
                timeZoneID: F.india,
                now: F.date(2026, 10, 21),
            )
        )
        #expect(change == .replaced([]))
        #expect(repository.snapshot == before)
    }
}

import Foundation
import LittleOrbitDomain
import Testing

/// #34 P33: the refund sheet's payee is deleted elsewhere while the sheet is open. The typed name is kept and
/// saved as a payee again; Undo and Redo follow D191.4 and D191.4a. Names and amounts are made up.
@MainActor
@Suite("Refund payee re-created (P33)")
struct RefundPayeeRecreateTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = RefundFixture  // swiftlint:disable:this type_name

    private let now = F.date(2026, 10, 20)

    private struct Setup {
        let repository: FakeLedgerRepository
        let useCases: TransactionUseCases
        let refunds: DefaultRefundTransactionUseCase
        let refund: Transaction
    }

    /// Trailhead Sports' expense, its refund opened in the sheet, then the payee deleted in another window.
    private func setup() throws -> Setup {
        let trailhead = Payee(name: "Trailhead Sports", createdAt: R.october)
        var expense = R.expense(1_000)
        expense.payeeID = trailhead.id
        let repository = try R.repository()
        try repository.savePayee(trailhead)
        try repository.saveTransaction(expense)
        let refunds = DefaultRefundTransactionUseCase(repository: repository)
        var refund = try #require(try refunds.newRefund(of: expense.id, now: now, timeZoneID: F.india))
        refund.amount = 300
        try repository.deletePayee(id: trailhead.id)
        return Setup(
            repository: repository,
            useCases: TransactionUseCases(repository: repository),
            refunds: refunds,
            refund: refund,
        )
    }

    private func livePayees(_ repository: FakeLedgerRepository, named name: String) throws -> [Payee] {
        try repository.payees().filter { $0.isLive(named: name) }
    }

    @Test("P33: the typed name is saved as a payee again; one Undo removes both, and Redo restores both")
    func recreatedUndoRedo() throws {
        let setup = try setup()
        let change = try setup.refunds.save(setup.refund, payeeName: "Trailhead Sports")
        let payee = try #require(try livePayees(setup.repository, named: "Trailhead Sports").first)
        #expect(try setup.repository.stored(setup.refund.id)?.payeeID == payee.id)
        #expect(change == .createdPayees([payee], .added([setup.refund.id])))
        let redo = try setup.useCases.changes.revertNow(change)
        #expect(try setup.repository.stored(setup.refund.id) == nil)
        #expect(try livePayees(setup.repository, named: "Trailhead Sports").isEmpty)
        _ = try setup.useCases.changes.revertNow(redo)
        #expect(try setup.repository.stored(setup.refund.id)?.payeeID == payee.id)
        #expect(try livePayees(setup.repository, named: "Trailhead Sports").map(\.id) == [payee.id])
    }

    @Test("P33: a payee with that name added by then is used, and Undo leaves it")
    func existingByThen() throws {
        let setup = try setup()
        let added = Payee(name: "Trailhead Sports", createdAt: now)
        try setup.repository.savePayee(added)
        let change = try setup.refunds.save(setup.refund, payeeName: "Trailhead Sports")
        #expect(change == .added([setup.refund.id]))
        #expect(try setup.repository.stored(setup.refund.id)?.payeeID == added.id)
        _ = try setup.useCases.changes.revertNow(change)
        #expect(try livePayees(setup.repository, named: "Trailhead Sports").map(\.id) == [added.id])
    }

    @Test("P33, D191.4a: the re-created payee used on another transaction before Undo stays; Undo removes the refund")
    func usedBeforeUndo() throws {
        let setup = try setup()
        let change = try setup.refunds.save(setup.refund, payeeName: "Trailhead Sports")
        let payee = try #require(try livePayees(setup.repository, named: "Trailhead Sports").first)
        var other = R.expense(50)
        other.payeeID = payee.id
        try setup.repository.saveTransaction(other)
        _ = try setup.useCases.changes.revertNow(change)
        #expect(try setup.repository.stored(setup.refund.id) == nil)
        #expect(try livePayees(setup.repository, named: "Trailhead Sports").map(\.id) == [payee.id])
    }

    @Test("P33, D191.4a: the re-created payee renamed before Undo stays; Undo removes the refund")
    func renamedBeforeUndo() throws {
        let setup = try setup()
        let change = try setup.refunds.save(setup.refund, payeeName: "Trailhead Sports")
        var payee = try #require(try livePayees(setup.repository, named: "Trailhead Sports").first)
        payee.name = "Trailhead Outlet"
        try setup.repository.savePayee(payee)
        _ = try setup.useCases.changes.revertNow(change)
        #expect(try setup.repository.stored(setup.refund.id) == nil)
        #expect(try livePayees(setup.repository, named: "Trailhead Outlet").map(\.id) == [payee.id])
    }

    @Test("P34: the payee goes on the refund only; the expense, with no payee, is unchanged through Undo and Redo")
    func expenseWithoutPayeeUntouched() throws {
        let expense = R.expense(1_000)
        let repository = try R.repository([expense])
        let useCases = TransactionUseCases(repository: repository)
        let refunds = DefaultRefundTransactionUseCase(repository: repository)
        var refund = try #require(try refunds.newRefund(of: expense.id, now: now, timeZoneID: F.india))
        refund.amount = 300
        let before = try #require(try repository.stored(expense.id))
        let change = try refunds.save(refund, payeeName: "Trailhead Sports")
        let payee = try #require(try livePayees(repository, named: "Trailhead Sports").first)
        #expect(try repository.stored(refund.id)?.payeeID == payee.id)
        #expect(try repository.stored(expense.id) == before)
        #expect(try repository.stored(expense.id)?.payeeID == nil)
        let redo = try useCases.changes.revertNow(change)
        #expect(try repository.stored(expense.id) == before)
        _ = try useCases.changes.revertNow(redo)
        #expect(try repository.stored(expense.id) == before)
    }

    @Test("P34: with its payee deleted, the expense keeps its fields; Undo and Redo of the refund leave it unchanged")
    func expenseWithDeletedPayeeUntouched() throws {
        let setup = try setup()
        let expenseID = try #require(setup.refund.refundOfID)
        let before = try #require(try setup.repository.stored(expenseID))
        let change = try setup.refunds.save(setup.refund, payeeName: "Trailhead Sports")
        let payee = try #require(try livePayees(setup.repository, named: "Trailhead Sports").first)
        #expect(before.payeeID != payee.id)
        #expect(try setup.repository.stored(expenseID) == before)
        let redo = try setup.useCases.changes.revertNow(change)
        #expect(try setup.repository.stored(expenseID) == before)
        _ = try setup.useCases.changes.revertNow(redo)
        #expect(try setup.repository.stored(expenseID) == before)
    }
}

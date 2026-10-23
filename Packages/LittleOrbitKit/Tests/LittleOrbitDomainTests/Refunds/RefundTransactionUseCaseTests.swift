import Foundation
import LittleOrbitDomain
import Testing

/// The refund sheet's use case (#34, D33, D35, D65, D97.4): prefill, the live check, and a save that is one
/// Undo step or writes nothing. Names and amounts are made up.
@MainActor
@Suite("Refund use case")
struct RefundTransactionUseCaseTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = RefundFixture  // swiftlint:disable:this type_name

    private let now = F.date(2026, 10, 20)

    @Test("S14: a new refund opens with the remaining amount, now, and the expense's category and account")
    func prefill() throws {
        let expense = R.expense(1_000, in: R.shoppingID)
        let repository = try R.repository([expense, R.refund(300, of: expense)])
        let refunds = DefaultRefundTransactionUseCase(repository: repository)
        let refund = try #require(try refunds.newRefund(of: expense.id, now: now, timeZoneID: F.india))
        #expect(refund.amount == 700)
        #expect(refund.refundOfID == expense.id && refund.isRefund && refund.type == .income)
        #expect(refund.categoryID == R.shoppingID)
        #expect(refund.accountID == F.savingsID)
        #expect(refund.date == now && refund.timeZoneID == F.india)
        #expect(try repository.stored(refund.id) == nil)
    }

    @Test("Refund isn't offered for income, a refund or a record that's gone")
    func notOffered() throws {
        let expense = R.expense(1_000)
        let refund = R.refund(300, of: expense)
        let income = Transaction(
            type: .income,
            amount: 50,
            date: R.october,
            timeZoneID: F.india,
            accountID: F.savingsID,
            categoryID: R.salaryID,
            createdAt: R.october,
        )
        let repository = try R.repository([expense, refund, income])
        let refunds = DefaultRefundTransactionUseCase(repository: repository)
        for id in [income.id, refund.id, UUID()] {
            #expect(try refunds.newRefund(of: id, now: now, timeZoneID: F.india) == nil)
        }
    }

    @Test("S16: the check counts other refunds, not this one, and carries the refundable amount")
    func check() throws {
        let expense = R.expense(1_000)
        let repository = try R.repository([expense, R.refund(300, of: expense)])
        let refunds = DefaultRefundTransactionUseCase(repository: repository)
        var refund = try #require(try refunds.newRefund(of: expense.id, now: now, timeZoneID: F.india))
        refund.amount = 701
        let check = try #require(try refunds.check(refund))
        #expect(check.expense == expense)
        #expect(check.refunded == 300)
        #expect(check.refundable == 700)
        #expect(check.issues == [.exceedsRefundable(700)])
        refund.amount = 700
        #expect(try refunds.check(refund)?.issues == [])
    }

    @Test("A saved refund is one step: .added, and one Undo removes it")
    func saveAndUndo() throws {
        let expense = R.expense(1_000)
        let repository = try R.repository([expense])
        let useCases = TransactionUseCases(repository: repository)
        let refunds = DefaultRefundTransactionUseCase(repository: repository)
        let refund = try #require(try refunds.newRefund(of: expense.id, now: now, timeZoneID: F.india))
        let change = try refunds.save(refund, payeeName: "")
        #expect(change == .added([refund.id]))
        #expect(try repository.stored(refund.id) == refund)
        _ = try useCases.changes.revertNow(change)
        #expect(try repository.stored(refund.id) == nil)
        #expect(try repository.stored(expense.id) == expense)
    }

    @Test("S15, S49: a blocked save throws its issues and writes nothing")
    func blocked() throws {
        let expense = R.expense(1_000)
        let repository = try R.repository([expense])
        let refunds = DefaultRefundTransactionUseCase(repository: repository)
        var refund = try #require(try refunds.newRefund(of: expense.id, now: now, timeZoneID: F.india))
        refund.accountID = F.usdID
        refund.date = F.date(2026, 10, 9)
        let before = repository.snapshot
        let day = CalendarDay(year: 2026, month: 10, day: 10)
        #expect(throws: RefundBlocked(issues: [.currencyMismatch, .dateBeforeOriginal(day)])) {
            try refunds.save(refund, payeeName: "")
        }
        #expect(repository.snapshot == before)
    }

    @Test("An expense deleted since the sheet opened: no check, and the save writes nothing")
    func expenseGone() throws {
        let expense = R.expense(1_000)
        let repository = try R.repository([expense])
        let refunds = DefaultRefundTransactionUseCase(repository: repository)
        let refund = try #require(try refunds.newRefund(of: expense.id, now: now, timeZoneID: F.india))
        try repository.deleteTransaction(id: expense.id)
        #expect(try refunds.check(refund) == nil)
        #expect(throws: LedgerValidationError.refundOriginalMissing) { try refunds.save(refund, payeeName: "") }
        #expect(try repository.stored(refund.id) == nil)
    }

    @Test("D234.4, D235: the payee as typed: an existing name reuses it, a new one is created and Undo removes it")
    func payeeAsTyped() throws {
        let expense = R.expense(1_000)
        let repository = try R.repository([expense])
        let useCases = TransactionUseCases(repository: repository)
        let refunds = DefaultRefundTransactionUseCase(repository: repository)
        let existing = Payee(name: "Trailhead Sports", createdAt: R.october)
        try repository.savePayee(existing)
        var first = try #require(try refunds.newRefund(of: expense.id, now: now, timeZoneID: F.india))
        first.amount = 100
        _ = try refunds.save(first, payeeName: "  Trailhead Sports ")
        #expect(try repository.stored(first.id)?.payeeID == existing.id)
        var second = try #require(try refunds.newRefund(of: expense.id, now: now, timeZoneID: F.india))
        second.amount = 100
        let change = try refunds.save(second, payeeName: "Trailhead Outlet")
        let created = try #require(try repository.payees().first { $0.name == "Trailhead Outlet" })
        #expect(change == .createdPayees([created], .added([second.id])))
        #expect(try repository.stored(second.id)?.payeeID == created.id)
        _ = try useCases.changes.revertNow(change)
        #expect(try repository.stored(second.id) == nil)
        #expect(try repository.payees().contains { $0.id == created.id } == false)
    }
}

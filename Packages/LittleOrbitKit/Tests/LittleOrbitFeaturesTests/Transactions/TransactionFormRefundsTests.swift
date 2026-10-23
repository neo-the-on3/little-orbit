import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// An expense with refunds in the editor (D222.2, D222.3; P17, P18). Names and amounts are made up.
@MainActor
@Suite("Edit sheet: an expense with refunds")
struct TransactionFormRefundsTests {
    typealias F = RefundsFeatureFixture  // swiftlint:disable:this type_name

    private func form(_ id: UUID, in fixture: F) -> TransactionFormViewModel {
        TransactionFormViewModel(
            useCases: fixture.useCases,
            mode: .edit(id),
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: F.kolkata)!,
            now: { F.now },
        )
    }

    @Test("P17: Edit Expense with no switch and the refunds footnote; without refunds the switch is back")
    func hidesSwitch() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let refund = try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let model = form(expense.id, in: fixture)
        #expect(model.title == "Edit Expense")
        #expect(!model.showsTypeSwitch)
        #expect(
            model.refundsFootnote
                == "Refunded ₹300.00 of ₹1,000.00. While these refunds exist, the amount can’t go below ₹300.00 and the expense can’t become income."
        )
        try fixture.repository.deleteTransaction(id: refund.id)
        let after = form(expense.id, in: fixture)
        #expect(after.showsTypeSwitch)
        #expect(after.refundsFootnote == nil)
    }

    @Test("P18: a refund recorded while the editor is on Income saves nothing and says why (D222.3)")
    func fallback() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let model = form(expense.id, in: fixture)
        model.type = .income
        try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let before = try fixture.repository.transactions()
        #expect(model.save() == nil)
        #expect(model.errorMessage == "This expense has refunds, so it can’t become income.")
        #expect(try fixture.repository.transactions() == before)
    }

    @Test("P40, D247: a linked refund opens as Edit Refund with no Expense/Income switch")
    func linkedRefund() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let refund = try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let model = form(refund.id, in: fixture)
        #expect(model.title == "Edit Refund")
        #expect(model.allowedTypes == [.income])
        #expect(!model.showsTypeSwitch)
        #expect(model.type == .income)
    }

    @Test("P40, D247: an orphaned refund opens as Edit Refund with no Expense/Income switch")
    func orphanedRefund() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let refund = try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        try fixture.repository.deleteTransaction(id: expense.id)
        let model = form(refund.id, in: fixture)
        #expect(model.title == "Edit Refund")
        #expect(model.allowedTypes == [.income])
        #expect(!model.showsTypeSwitch)
    }

    @Test("D225.1: refunds recorded or deleted in another window update an open Edit Expense, keeping the user’s edits")
    func followsLiveRefunds() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let model = form(expense.id, in: fixture)
        #expect(model.showsTypeSwitch)
        model.expressionInput = "1200"
        model.note = "Shoes and socks"
        model.payeeText = "Trailhead Outlet"
        let refund = try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        model.reload()
        #expect(!model.showsTypeSwitch)
        #expect(
            model.refundsFootnote
                == "Refunded ₹300.00 of ₹1,200.00. While these refunds exist, the amount can’t go below ₹300.00 and the expense can’t become income."
        )
        #expect(model.expressionInput == "1200")
        #expect(model.note == "Shoes and socks")
        #expect(model.payeeText == "Trailhead Outlet")
        try fixture.repository.deleteTransaction(id: refund.id)
        model.reload()
        #expect(model.showsTypeSwitch)
        #expect(model.refundsFootnote == nil)
        #expect(model.expressionInput == "1200")
        #expect(model.note == "Shoes and socks")
    }

    @Test("D225.1: an editor the user already switched to Income keeps the switch when a refund arrives")
    func keepsIncome() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let model = form(expense.id, in: fixture)
        model.type = .income
        try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        model.reload()
        #expect(model.type == .income)
        #expect(model.showsTypeSwitch)
    }
}

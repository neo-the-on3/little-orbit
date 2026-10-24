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
                == "Refunded ₹300.00 of ₹1,000.00. While these refunds exist, the amount can’t go below ₹300.00 and the expense can’t become income or be split."
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

    @Test("D258.1, P45: Edit Refund saves up to ₹1,000.00; ₹1,001.00 says only ₹1,000.00 is refundable")
    func editRefundOverCap() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let refund = try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        try expectCap(
            editing: refund,
            limit: "1000",
            over: "1001",
            message: "Only ₹1,000.00 is refundable.",
            in: fixture,
        )
    }

    @Test("D258.3, P45: with a second ₹200.00 refund, Edit Refund saves ₹800.00; ₹801.00 says only ₹800.00")
    func editRefundOverCapWithAnother() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let refund = try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        try fixture.refund(200, of: expense, on: F.date(2026, 10, 19, zone: F.kolkata))
        try expectCap(editing: refund, limit: "800", over: "801", message: "Only ₹800.00 is refundable.", in: fixture)
    }

    /// `over` is refused with `message`: nothing is written, no Undo step, and the sheet stays open with the typed
    /// amount (D258.1, D191.3). Then `limit` itself saves.
    private func expectCap(
        editing refund: Transaction,
        limit: String,
        over: String,
        message: String,
        in fixture: F,
    ) throws {
        let model = form(refund.id, in: fixture)
        model.expressionInput = over
        let before = try fixture.repository.transactions()
        let window = TestWindow(fixture.useCases)
        // The sheet records a change and closes only when save returns one.
        let refused = model.save()
        #expect(refused == nil)
        if let refused {
            window.history.record(refused)
        }
        #expect(model.errorMessage == message)
        #expect(try fixture.repository.transactions() == before)
        #expect(!window.history.canUndo)
        #expect(model.expressionInput == over)
        model.errorMessage = nil
        model.expressionInput = limit
        let change = try #require(model.save())
        #expect(change.transactionIDs == [refund.id])
        #expect(model.errorMessage == nil)
        let stored = try fixture.repository.transactions().first { $0.id == refund.id }
        #expect(stored?.amount == Decimal(string: limit))
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
                == "Refunded ₹300.00 of ₹1,200.00. While these refunds exist, the amount can’t go below ₹300.00 and the expense can’t become income or be split."
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

    @Test("D117.5, S61: Edit Expense lists its refunds, oldest first, with day, signed amount and account")
    func refundRows() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let later = try fixture.refund(200, of: expense, on: F.date(2026, 10, 21, zone: F.kolkata))
        let first = try fixture.refund(300, of: expense, on: F.date(2026, 10, 20, zone: F.kolkata))
        let model = form(expense.id, in: fixture)
        let account = fixture.savings.name
        #expect(
            model.refundRows == [
                ExpenseRefundRow(id: first.id, date: "20 Oct", amount: "+₹300.00", account: account),
                ExpenseRefundRow(id: later.id, date: "21 Oct", amount: "+₹200.00", account: account),
            ]
        )
        #expect(form(first.id, in: fixture).refundRows.isEmpty)
    }

    @Test(
        "B3: a refund with an unknown or empty stored zone reads its day in UTC, not the device zone",
        arguments: ["Mars/Olympus", ""],
    )
    func refundRowUnknownZone(_ zone: String) throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        // 20 Oct 20:00 UTC is already 21 Oct in Kolkata, the device zone here.
        let refund = try fixture.refund(300, of: expense, on: F.date(2026, 10, 20, 20, 0, zone: "UTC"), zone: "UTC")
        var snapshot = try fixture.repository.ledgerSnapshot()
        let index = try #require(snapshot.transactions.firstIndex { $0.id == refund.id })
        // Written straight into the store, the way a backup from another device could hold it.
        snapshot.transactions[index].timeZoneID = zone
        try fixture.repository.replaceLedger(with: snapshot)
        let model = form(expense.id, in: fixture)
        #expect(model.refundRows.map(\.date) == ["20 Oct"])
    }
}

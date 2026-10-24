import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// Duplicate from a row's menus, the iOS swipe and ⌘D (D65, D117.2, D117.3, #31). Names and amounts are made up.
@MainActor
@Suite("Account history: Duplicate")
struct AccountHistoryDuplicateTests {
    typealias F = RefundsFeatureFixture  // swiftlint:disable:this type_name

    private static let expenseDate = F.date(2026, 10, 17, zone: F.kolkata)

    private func history(_ fixture: F) -> AccountHistoryViewModel {
        let history = AccountHistoryViewModel(
            useCases: fixture.useCases,
            accountID: fixture.savings.id,
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: F.kolkata)!,
            now: { F.now },
        )
        history.load()
        return history
    }

    @Test("S19, S43, S59: ⌘D works on one expense, income or transfer row, never on a refund or two rows")
    func duplicateTarget() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        let other = try fixture.expense(200, on: Self.expenseDate)
        let refund = try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let transfer = try fixture.transfer(100, from: fixture.savings, to: fixture.groceryCash)
        let model = history(fixture)
        #expect(model.duplicateTarget([expense.id]) == expense.id)
        #expect(model.duplicateTarget([transfer.id]) == transfer.id)
        #expect(model.duplicateTarget([refund.id]) == nil)
        #expect(model.duplicateTarget([expense.id, other.id]) == nil)
        #expect(model.duplicateTarget([]) == nil)
        #expect(model.refundIDs == [refund.id])
    }

    @Test("S27, S29: Duplicate copies the expense dated now as one Undo step that removes only the copy")
    func duplicateAndUndo() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let model = history(fixture)
        let change = try #require(model.duplicate(id: expense.id))
        let copyID = try #require(change.transactionIDs.first)
        let copy = try #require(try fixture.repository.transactions().first { $0.id == copyID })
        #expect(copy.amount == 1_000 && copy.date == F.now && copy.refundOfID == nil)
        #expect(model.allRows.contains { $0.id == copyID })
        let window = TestWindow(fixture.useCases)
        window.history.record(change)
        #expect(window.history.undoTitle == "Duplicate Transaction in Everyday Savings")
        window.history.undo()
        #expect(try fixture.repository.transactions().contains { $0.id == copyID } == false)
        #expect(try fixture.repository.transactions().first { $0.id == expense.id } == expense)
    }

    @Test("A refund can't be duplicated: nothing is written, and the failure says so")
    func refundNotDuplicated() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        let refund = try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let model = history(fixture)
        let before = try fixture.repository.transactions()
        #expect(model.duplicate(id: refund.id) == nil)
        #expect(model.errorMessage == "Something went wrong saving your change. Please try again.")
        #expect(try fixture.repository.transactions() == before)
    }
}

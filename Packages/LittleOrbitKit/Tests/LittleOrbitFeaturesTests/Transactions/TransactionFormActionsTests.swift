import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Edit Expense's Delete Expense button and its footnote (Figma 175:1994, D97.2, D112). Names and amounts are
/// made up.
@MainActor
@Suite("Edit sheet actions")
struct TransactionFormActionsTests {
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

    @Test("An expense with a refund: Delete Expense says its refunds stay in Shopping, labelled")
    func expenseWithRefund() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        try fixture.refund(300, of: expense, on: F.date(2026, 10, 20, zone: F.kolkata))
        let model = form(expense.id, in: fixture)
        #expect(model.deleteTitle == "Delete Expense")
        #expect(
            model.deleteFootnote
                == "Deleting the expense keeps its refunds in Shopping, labelled “Refund (original deleted)”. Undo links them again."
        )
    }

    @Test("An expense with no refunds has no footnote; a refund reads Delete Transaction")
    func noFootnote() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let refund = try fixture.refund(300, of: expense, on: F.date(2026, 10, 20, zone: F.kolkata))
        let other = try fixture.expense(500, on: F.date(2026, 10, 18, zone: F.kolkata))
        #expect(form(other.id, in: fixture).deleteTitle == "Delete Expense")
        #expect(form(other.id, in: fixture).deleteFootnote == nil)
        #expect(form(refund.id, in: fixture).deleteTitle == "Delete Transaction")
        #expect(form(refund.id, in: fixture).deleteFootnote == nil)
    }

    @Test("P38, D242.4: Delete Expense with an unsaved change is the normal single delete, undone without the change")
    func deleteWithUnsavedChange() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        let model = form(expense.id, in: fixture)
        model.expressionInput = "1200"
        #expect(model.hasUnsavedInput)
        #expect(!TransactionFormAction.delete.asksToDiscardEdits)
        let history = AccountHistoryViewModel(
            useCases: fixture.useCases,
            accountID: fixture.savings.id,
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: F.kolkata)!,
            now: { F.now },
        )
        history.load()
        let change = try #require(history.requestDelete(ids: [expense.id]))
        #expect(history.deletePrompt == nil)
        let window = TestWindow(fixture.useCases)
        window.history.record(change)
        #expect(window.history.undoTitle == "Delete Transaction in Everyday Savings")
        window.history.undo()
        #expect(try fixture.repository.transactions().first { $0.id == expense.id }?.amount == 1_000)
    }

    @Test("P38: with no unsaved change, none of the three asks to discard")
    func noUnsavedChange() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        #expect(!form(expense.id, in: fixture).hasUnsavedInput)
        #expect(TransactionFormAction.refund.asksToDiscardEdits && TransactionFormAction.duplicate.asksToDiscardEdits)
    }
}

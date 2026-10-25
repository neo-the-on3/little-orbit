import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Change Budget Limit and Delete Budget on the iOS budget detail (#25 part 4): the edit limit frame (#25 AC 4),
/// the delete frame with the D307 amendment's quotes, their Undo steps (D307.8) and the D309 and D310 messages.
@MainActor
@Suite("Budget detail actions (#25)")
struct BudgetDetailActionsTests {
    typealias T = TransactionFeatureFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFeatureFixture  // swiftlint:disable:this type_name

    private struct Setup {
        let repository: InMemoryLedgerRepository
        let window: TestWindow
        let model: BudgetDetailViewModel
    }

    private func setup(_ budget: Budget) throws -> Setup {
        let repository = try B.repository([budget])
        let updates = LedgerUpdates()
        let window = TestWindow(
            TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
            updates: updates,
        )
        let history = window.history
        let model = try #require(
            BudgetDetailViewModelTests.feature(repository, updates: updates).makeDetail(budget.id) { history }
        )
        model.load()
        return Setup(repository: repository, window: window, model: model)
    }

    @Test("Change Budget Limit: the field starts at the limit, errors show per field, and Save needs a new limit")
    func limitField() throws {
        let setup = try setup(B.budget("Eating out", limit: 7_000))
        let model = setup.model
        model.beginLimitChange()
        #expect(model.limitText == "7,000.00")
        #expect(model.limitFootnote == "Was ₹7,000.00.")
        #expect(model.limitError == nil)
        #expect(model.canChangeLimit == false)
        model.limitText = "0"
        #expect(model.limitError == "Enter a limit above ₹0.")
        model.limitText = "abc"
        #expect(model.limitError == "Enter a limit like 1,25,000.00.")
        model.limitText = "-5"
        #expect(model.limitError == "Enter a limit above ₹0.", "D309.2")
        model.limitText = "8000"
        #expect(model.limitError == nil)
        #expect(model.canChangeLimit)
    }

    @Test("No past periods: Save applies the limit at once, as one “Change Budget Limit” Undo step")
    func changeLimitNow() throws {
        let setup = try setup(B.budget("Eating out", limit: 7_000))
        setup.model.beginLimitChange()
        setup.model.limitText = "8000"
        #expect(setup.model.changeLimit() == .saved)
        #expect(try setup.repository.budgets().first?.limits.map(\.amount) == [8_000])
        #expect(setup.model.header?.subline == "of ₹8,000.00 available")
        #expect(setup.window.history.undoTitle == "Change Budget Limit Eating out")
        setup.window.history.undo()
        #expect(try setup.repository.budgets().first?.limits.map(\.amount) == [7_000])
    }

    @Test("#25 AC 4: with past periods it asks first, and applies from this period only")
    func changeLimitConfirm() throws {
        let setup = try setup(B.budget("Eating out", limit: 7_000, from: CalendarDay(year: 2026, month: 9, day: 1)))
        setup.model.beginLimitChange()
        setup.model.limitText = "8000"
        #expect(setup.model.changeLimit() == .confirm)
        #expect(setup.model.limitConfirmationTitle == "Change limit to ₹8,000.00?")
        #expect(
            setup.model.limitConfirmationMessage
                == "Applies from this period (\(BudgetDetailViewModelTests.october)) onwards. "
                + "Earlier periods keep their limit of ₹7,000.00."
        )
        #expect(try setup.repository.budgets().first?.limits.count == 1, "Nothing is saved before the answer")
        #expect(setup.model.changeLimit(confirmed: true) == .saved)
        let limits = try #require(try setup.repository.budgets().first?.orderedLimits)
        #expect(limits.map(\.amount) == [7_000, 8_000])
        #expect(limits.last?.startDay == CalendarDay(year: 2026, month: 10, day: 1))
    }

    @Test("D309: a budget deleted while Change Budget Limit is open can't be saved, and says so")
    func changeLimitDeleted() throws {
        let budget = B.budget("Eating out", limit: 7_000)
        let setup = try setup(budget)
        setup.model.beginLimitChange()
        setup.model.limitText = "8000"
        try setup.repository.deleteBudget(id: budget.id)
        #expect(setup.model.changeLimit() == .notSaved)
        #expect(
            setup.model.alert
                == CategoryAlert(title: "Couldn’t Save Changes", message: "This budget no longer exists.")
        )
    }

    @Test("Delete Budget: the alert, then one “Delete Budget” step that Undo reverses with the same budget")
    func delete() throws {
        let budget = B.budget("Shopping", limit: 5_000)
        let setup = try setup(budget)
        #expect(setup.model.deleteTitle == "Delete the “Shopping” budget?")
        #expect(
            setup.model.deleteMessage
                == "The budget and its history are removed. Your transactions aren’t changed and still count in Reports."
        )
        #expect(setup.model.delete())
        #expect(try setup.repository.budgets().isEmpty)
        #expect(setup.window.history.undoTitle == "Delete Budget Shopping")
        setup.window.history.undo()
        #expect(try setup.repository.budgets().map(\.id) == [budget.id])
        #expect(setup.window.history.redoTitle == "Delete Budget Shopping")
        setup.window.history.redo()
        #expect(try setup.repository.budgets().isEmpty)
    }

    @Test("D310.1: Undo Delete Budget when another budget took the name is stale: the alert, and the step goes")
    func undoDeleteNameTaken() throws {
        let setup = try setup(B.budget("Shopping", limit: 5_000))
        #expect(setup.model.delete())
        try setup.repository.saveBudget(B.budget("SHOPPING", limit: 1_000))
        setup.window.history.undo()
        #expect(setup.window.history.alert?.title == "Can’t Undo Delete Budget Shopping")
        #expect(
            setup.window.history.alert?.message == "There’s already a budget named “SHOPPING”. Nothing was changed."
        )
        #expect(try setup.repository.budgets().map(\.name) == ["SHOPPING"])
        #expect(setup.window.history.undoTitle == nil, "The stale step is dropped")
    }

    @Test("D310: Undo Delete Budget after one of its categories was deleted is stale, names it, and writes nothing")
    func undoDeleteCategoryDeleted() throws {
        let setup = try setup(B.budget("Shopping", limit: 5_000, categories: [B.eatingOutID, B.shoppingID]))
        #expect(setup.model.delete())
        try setup.repository.deleteCategory(id: B.eatingOutID, reassigningTo: nil)
        setup.window.history.undo()
        #expect(setup.window.history.alert?.title == "Can’t Undo Delete Budget Shopping")
        #expect(setup.window.history.alert?.message == "Eating out has been deleted. Nothing was changed.")
        #expect(try setup.repository.budgets().isEmpty, "Nothing is restored")
        #expect(setup.window.history.undoTitle == nil, "The stale step is dropped")
    }

    @Test("D309: deleting a budget that's already gone shows “This budget no longer exists.”")
    func deleteMissing() throws {
        let budget = B.budget("Shopping", limit: 5_000)
        let setup = try setup(budget)
        try setup.repository.deleteBudget(id: budget.id)
        #expect(setup.model.delete() == false)
        #expect(setup.model.alert?.message == "This budget no longer exists.")
    }
}

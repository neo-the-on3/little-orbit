import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// The Mac's Duplicate Budget (#25 part 5): the copy's name (D307.6), its one Undo step (D307.8) and the D310.1
/// stale step, from the budget detail, which the Mac list's right-click Duplicate uses too.
@MainActor
@Suite("Budget duplicate (#25)")
struct BudgetDuplicateTests {
    typealias T = TransactionFeatureFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFeatureFixture  // swiftlint:disable:this type_name

    private struct Setup {
        let repository: InMemoryLedgerRepository
        let window: TestWindow
        let feature: BudgetsFeature
        let model: BudgetDetailViewModel
    }

    private func setup(_ budgets: [Budget]) throws -> Setup {
        let repository = try B.repository(budgets)
        let updates = LedgerUpdates()
        let window = TestWindow(
            TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
            updates: updates,
        )
        let history = window.history
        let feature = BudgetDetailViewModelTests.feature(repository, updates: updates)
        let id = try #require(budgets.first?.id)
        let model = try #require(feature.makeDetail(id) { history })
        model.load()
        return Setup(repository: repository, window: window, feature: feature, model: model)
    }

    @Test("D307.6: Duplicate makes “Eating out copy” at once, as one “Duplicate Budget” step Undo reverses")
    func duplicate() throws {
        let original = B.budget("Eating out", limit: 7_000, carriesOverOverspending: true)
        let setup = try setup([original])
        #expect(setup.model.canDuplicate)
        let copyID = try #require(setup.model.duplicate())
        let copy = try #require(try setup.repository.budgets().first { $0.id == copyID })
        #expect(copy.name == "Eating out copy")
        #expect(copy.carriesOverOverspending)
        #expect(copy.limits.map(\.amount) == [7_000])
        #expect(setup.window.history.undoTitle == "Duplicate Budget Eating out copy")

        setup.window.history.undo()
        #expect(try setup.repository.budgets().map(\.id) == [original.id])
        #expect(setup.window.history.redoTitle == "Duplicate Budget Eating out copy")
        setup.window.history.redo()
        #expect(try setup.repository.budgets().contains { $0.id == copyID })
    }

    @Test("D307.6: a second Duplicate is “Eating out copy 2”, like the Finder")
    func secondCopy() throws {
        let setup = try setup([B.budget("Eating out", limit: 7_000)])
        _ = try #require(setup.model.duplicate())
        _ = try #require(setup.model.duplicate())
        #expect(
            try setup.repository.budgets().map(\.name) == ["Eating out", "Eating out copy", "Eating out copy 2"]
        )
        #expect(setup.window.history.undoTitle == "Duplicate Budget Eating out copy 2")
    }

    @Test("D310.1: Redo Duplicate Budget after another budget took the copy's name is stale, and the step goes")
    func redoNameTaken() throws {
        let setup = try setup([B.budget("Eating out", limit: 7_000)])
        _ = try #require(setup.model.duplicate())
        setup.window.history.undo()
        try setup.repository.saveBudget(B.budget("EATING OUT COPY", limit: 1_000, categories: [B.shoppingID]))
        setup.window.history.redo()
        #expect(setup.window.history.alert?.title == "Can’t Redo Duplicate Budget Eating out copy")
        #expect(
            setup.window.history.alert?.message
                == "There’s already a budget named “EATING OUT COPY”. Nothing was changed."
        )
        #expect(!setup.window.history.canUndo && !setup.window.history.canRedo, "A stale step is removed")
    }

    @Test("D307.5: a budget with no categories left offers no Duplicate, and writes nothing")
    func noCategories() throws {
        let setup = try setup([B.budget("Shopping", limit: 5_000, categories: [B.shoppingID])])
        try setup.repository.deleteCategory(id: B.shoppingID, reassigningTo: nil)
        setup.model.load()
        #expect(setup.model.state == .noCategories)
        #expect(!setup.model.canDuplicate)
        #expect(setup.model.duplicate() == nil)
        #expect(try setup.repository.budgets().map(\.name) == ["Shopping"])
        #expect(setup.window.history.undoTitle == nil)
    }

    @Test("D309: duplicating a budget deleted elsewhere says “This budget no longer exists.”")
    func duplicateMissing() throws {
        let budget = B.budget("Shopping", limit: 5_000)
        let setup = try setup([budget])
        try setup.repository.deleteBudget(id: budget.id)
        #expect(setup.model.duplicate() == nil)
        #expect(
            setup.model.alert
                == CategoryAlert(title: "Couldn’t Save Changes", message: "This budget no longer exists.")
        )
    }
}

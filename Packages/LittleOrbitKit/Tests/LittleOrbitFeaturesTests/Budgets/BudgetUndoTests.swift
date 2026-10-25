import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Budget saves as steps of the window's Undo history (D307.8): the names, Undo and Redo, the stale messages
/// (D228.5, the D306 amendment) and the reload every save triggers (#25 AC 6).
@MainActor
@Suite("Budget Undo (#25)")
struct BudgetUndoTests {
    typealias T = TransactionFeatureFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFeatureFixture  // swiftlint:disable:this type_name

    private struct Setup {
        let repository: InMemoryLedgerRepository
        /// The budget writes, which can be made to fail for a while (X8).
        let writes: FailingBudgetWrites
        let budgets: DefaultBudgetUseCases
        let updates: LedgerUpdates
        let window: TestWindow
    }

    private func setup(_ budgets: [Budget] = []) throws -> Setup {
        let repository = try B.repository(budgets)
        let writes = FailingBudgetWrites(repository)
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let updates = LedgerUpdates()
        return Setup(
            repository: repository,
            writes: writes,
            budgets: DefaultBudgetUseCases(repository: writes, now: { T.now }),
            updates: updates,
            window: TestWindow(useCases, updates: updates),
        )
    }

    private func draft(_ name: String = "Eating out") -> BudgetDraft {
        BudgetDraft(
            name: name,
            limit: 8_000,
            currencyCode: "INR",
            categoryIDs: [B.eatingOutID],
            startDay: CalendarDay(year: 2026, month: 10, day: 1),
        )
    }

    private func step(
        _ setup: Setup,
        _ change: BudgetChange,
        _ action: BudgetUndoStep.Action,
        name: String,
    ) throws -> BudgetUndoStep {
        try #require(
            BudgetUndoStep.make(
                change,
                action: action,
                budgetName: name,
                categoryNames: [B.eatingOutID: "Eating out", B.shoppingID: "Shopping trips"],
                changes: setup.budgets,
            )
        )
    }

    @Test("D307.8: “Undo New Budget Eating out” deletes it; “Redo New Budget Eating out” puts it back")
    func newBudget() throws {
        let setup = try setup()
        let change = try setup.budgets.savedChange(draft(), today: T.today)
        let before = setup.updates.revision
        setup.window.history.record(try step(setup, change, .new, name: "Eating out"))
        #expect(setup.updates.revision == before + 1, "A save reloads every window (#25 AC 6)")
        #expect(setup.window.history.undoTitle == "New Budget Eating out")

        setup.window.history.undo()
        #expect(try setup.repository.budgets().isEmpty)
        #expect(setup.window.history.redoTitle == "New Budget Eating out")
        #expect(setup.window.announcements.last == "Undid New Budget Eating out")
        #expect(setup.updates.revision == before + 2)

        setup.window.history.redo()
        #expect(try setup.repository.budgets().map(\.name) == ["Eating out"])
        #expect(setup.window.history.undoTitle == "New Budget Eating out")
    }

    @Test("D307.8: “Undo Edit Budget Dining” puts the earlier version back, limit included")
    func editBudget() throws {
        let original = B.budget("Eating out", limit: 8_000)
        let setup = try setup([original])
        var edit = BudgetDraft(editing: original, today: T.today)
        edit.name = "Dining"
        edit.limit = 9_500
        let change = try setup.budgets.savedChange(edit, today: T.today)
        setup.window.history.record(try step(setup, change, .edit, name: "Dining"))
        #expect(setup.window.history.undoTitle == "Edit Budget Dining")
        setup.window.history.undo()
        let back = try #require(try setup.repository.budgets().first)
        #expect(back.name == "Eating out")
        #expect(back.limit(forPeriodStartingOn: back.startDay) == 8_000)
    }

    @Test("D307.8: Change Budget Limit is its own name")
    func changeLimitName() throws {
        let original = B.budget("Eating out", limit: 8_000)
        let setup = try setup([original])
        let change = try setup.budgets.limitChange(of: original.id, to: 6_000, today: T.today)
        setup.window.history.record(try step(setup, change, .changeLimit, name: "Eating out"))
        #expect(setup.window.history.undoTitle == "Change Budget Limit Eating out")
    }

    @Test("D307.8, D228.5: a budget changed since then: “Eating out has changed since then. Nothing was changed.”")
    func staleChanged() throws {
        let setup = try setup()
        let change = try setup.budgets.savedChange(draft(), today: T.today)
        setup.window.history.record(try step(setup, change, .new, name: "Eating out"))
        var other = try #require(try setup.repository.budgets().first)
        other.carriesOverUnspent = true
        try setup.repository.saveBudget(other)

        setup.window.history.undo()
        setup.window.settle()
        #expect(setup.window.history.alert?.title == "Can’t Undo New Budget Eating out")
        #expect(setup.window.history.alert?.message == "Eating out has changed since then. Nothing was changed.")
        #expect(try setup.repository.budgets().count == 1)
        #expect(!setup.window.history.canUndo && !setup.window.history.canRedo, "A stale step is removed")
    }

    @Test("D307.8: a budget deleted since then: “Dining has been deleted. Nothing was changed.”")
    func staleDeleted() throws {
        let original = B.budget("Eating out", limit: 8_000)
        let setup = try setup([original])
        var edit = BudgetDraft(editing: original, today: T.today)
        edit.name = "Dining"
        let change = try setup.budgets.savedChange(edit, today: T.today)
        setup.window.history.record(try step(setup, change, .edit, name: "Dining"))
        try setup.repository.deleteBudget(id: original.id)
        setup.window.history.undo()
        #expect(setup.window.history.alert?.message == "Dining has been deleted. Nothing was changed.")
    }

    @Test("D307.8, D306 amendment: a step that would put back a deleted category names the category")
    func staleCategory() throws {
        let original = B.budget("Eating out", limit: 8_000, categories: [B.eatingOutID, B.shoppingID])
        let setup = try setup([original])
        var edit = BudgetDraft(editing: original, today: T.today)
        edit.categoryIDs = [B.eatingOutID]
        let change = try setup.budgets.savedChange(edit, today: T.today)
        setup.window.history.record(try step(setup, change, .edit, name: "Eating out"))
        try setup.repository.deleteCategory(id: B.shoppingID, reassigningTo: nil)
        setup.window.history.undo()
        #expect(setup.window.history.alert?.title == "Can’t Undo Edit Budget Eating out")
        #expect(setup.window.history.alert?.message == "Shopping trips has been deleted. Nothing was changed.")
    }

    @Test("X8: a write that fails for a while says “Couldn’t Redo” and keeps the step, which works once it passes")
    func failureKeepsStep() throws {
        let setup = try setup()
        let change = try setup.budgets.savedChange(draft(), today: T.today)
        setup.window.history.record(try step(setup, change, .new, name: "Eating out"))
        setup.window.history.undo()
        setup.writes.fails = true
        setup.window.history.redo()
        setup.window.settle()
        #expect(setup.window.history.alert?.title == "Couldn’t Redo New Budget Eating out")
        #expect(try setup.repository.budgets().isEmpty, "A failed write changes nothing")
        setup.window.history.dismissAlert()
        #expect(setup.window.history.redoTitle == "New Budget Eating out")

        setup.writes.fails = false
        setup.window.history.redo()
        setup.window.settle()
        #expect(setup.window.history.alert == nil)
        #expect(try setup.repository.budgets().map(\.name) == ["Eating out"])
        #expect(setup.window.history.undoTitle == "New Budget Eating out")
    }

    @Test("D310.1: Redo New Budget after another budget took the name is stale: Can’t Redo, nothing written, step gone")
    func staleNameTakenRedo() throws {
        let setup = try setup()
        let change = try setup.budgets.savedChange(draft(), today: T.today)
        setup.window.history.record(try step(setup, change, .new, name: "Eating out"))
        setup.window.history.undo()
        try setup.repository.saveBudget(B.budget("eating OUT", limit: 100, categories: [B.shoppingID]))
        let before = try setup.repository.budgetLedger()

        setup.window.history.redo()
        setup.window.settle()
        #expect(setup.window.history.alert?.title == "Can’t Redo New Budget Eating out")
        #expect(
            setup.window.history.alert?.message == "There’s already a budget named “eating OUT”. Nothing was changed."
        )
        #expect(try setup.repository.budgetLedger() == before, "A stale step writes nothing")
        #expect(!setup.window.history.canUndo && !setup.window.history.canRedo, "A stale step is removed")
    }

    @Test("D310.1: Undo of a rename after another budget took the old name is stale: Can’t Undo, step gone")
    func staleNameTakenUndo() throws {
        let original = B.budget("Eating out", limit: 8_000)
        let setup = try setup([original])
        var edit = BudgetDraft(editing: original, today: T.today)
        edit.name = "Dining"
        let change = try setup.budgets.savedChange(edit, today: T.today)
        setup.window.history.record(try step(setup, change, .edit, name: "Dining"))
        try setup.repository.saveBudget(B.budget("Eating Out", limit: 100, categories: [B.shoppingID]))
        let before = try setup.repository.budgetLedger()

        setup.window.history.undo()
        setup.window.settle()
        #expect(setup.window.history.alert?.title == "Can’t Undo Edit Budget Dining")
        #expect(
            setup.window.history.alert?.message == "There’s already a budget named “Eating Out”. Nothing was changed."
        )
        #expect(try setup.repository.budgetLedger() == before)
        #expect(!setup.window.history.canUndo && !setup.window.history.canRedo)
    }

    @Test("D310.2: Undo of an edit puts back a budget with no categories exactly; Redo the edit again")
    func noCategoriesRestores() throws {
        let original = B.budget("Eating out", limit: 8_000, categories: [B.shoppingID])
        let setup = try setup([original])
        try setup.repository.deleteCategory(id: B.shoppingID, reassigningTo: nil)
        let emptied = try #require(try setup.repository.budgets().first)
        #expect(emptied.categoryIDs.isEmpty, "D307.5 keeps the budget with no categories")
        var edit = BudgetDraft(editing: emptied, today: T.today)
        edit.categoryIDs = [B.eatingOutID]
        let change = try setup.budgets.savedChange(edit, today: T.today)
        setup.window.history.record(try step(setup, change, .edit, name: "Eating out"))

        setup.window.history.undo()
        setup.window.settle()
        #expect(setup.window.history.alert == nil)
        let back = try #require(try setup.repository.budgets().first)
        #expect(back.categoryIDs.isEmpty)
        #expect(back.hasSameSettings(as: emptied))
        #expect(setup.window.history.redoTitle == "Edit Budget Eating out")

        setup.window.history.redo()
        #expect(try setup.repository.budgets().first?.categoryIDs == [B.eatingOutID])
    }

    @Test("D309.7: a deleted category whose name isn’t known reads “A category has been deleted. Nothing was changed.”")
    func staleUnknownCategory() throws {
        let original = B.budget("Eating out", limit: 8_000, categories: [B.eatingOutID, B.shoppingID])
        let setup = try setup([original])
        var edit = BudgetDraft(editing: original, today: T.today)
        edit.categoryIDs = [B.eatingOutID]
        let change = try setup.budgets.savedChange(edit, today: T.today)
        let step = try #require(
            BudgetUndoStep.make(
                change,
                action: .edit,
                budgetName: "Eating out",
                categoryNames: [:],
                changes: setup.budgets,
            )
        )
        setup.window.history.record(step)
        try setup.repository.deleteCategory(id: B.shoppingID, reassigningTo: nil)
        setup.window.history.undo()
        #expect(setup.window.history.alert?.message == "A category has been deleted. Nothing was changed.")
    }

    @Test("A budget step and a transaction step share the window's history, newest first")
    func sharedHistory() throws {
        let setup = try setup()
        let change = try setup.budgets.savedChange(draft(), today: T.today)
        setup.window.history.record(try step(setup, change, .new, name: "Eating out"))
        let useCases = TransactionUseCases(repository: setup.repository, categoryNames: CatalogDefaultCategoryNames())
        let expense = B.expense(300)
        try setup.repository.saveTransaction(expense)
        setup.window.history.record(try useCases.changes.remove(ids: [expense.id]))
        #expect(setup.window.undoManager.undoNames.count == 2)
        setup.window.history.undo()
        #expect(setup.window.history.undoTitle == "New Budget Eating out")
        setup.window.history.undo()
        #expect(try setup.repository.budgets().isEmpty)
    }

    @Test("A save whose result can't be read back has no step, says so, and still reloads (D187.5)")
    func unreadable() throws {
        let setup = try setup()
        let before = setup.updates.revision
        setup.window.history.recordWithoutStep()
        #expect(setup.updates.revision == before + 1)
        #expect(setup.window.history.alert?.message == UndoText.unreadableChange)
        #expect(!setup.window.history.canUndo)
    }
}

/// The budget writes of an in-memory store, which throw while `fails` is on, like a full disk: a failure that
/// passes, so a kept step can work later (X8). Reads always go through.
@MainActor
final class FailingBudgetWrites: BudgetRepository {
    struct WriteFailure: Error {}

    private let base: InMemoryLedgerRepository
    var fails = false

    init(_ base: InMemoryLedgerRepository) {
        self.base = base
    }

    func budgets() throws -> [Budget] {
        try base.budgets()
    }

    func saveBudget(_ budget: Budget) throws {
        try check()
        try base.saveBudget(budget)
    }

    func restoreBudget(_ budget: Budget) throws {
        try check()
        try base.restoreBudget(budget)
    }

    func changeBudgetLimit(
        of budgetID: UUID,
        to amount: Decimal,
        fromPeriodStartingOn periodStart: CalendarDay,
    ) throws {
        try check()
        try base.changeBudgetLimit(of: budgetID, to: amount, fromPeriodStartingOn: periodStart)
    }

    func deleteBudget(id: UUID) throws {
        try check()
        try base.deleteBudget(id: id)
    }

    func budgetLedger() throws -> LedgerSnapshot {
        try base.budgetLedger()
    }

    private func check() throws {
        if fails {
            throw WriteFailure()
        }
    }
}

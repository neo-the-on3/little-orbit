import Foundation
import LittleOrbitDomain
import Testing

/// Budget saves as revertible changes (D307.8) and the “Recalculate Past Periods?” rule (D307.7), for #25 part 3.
@MainActor
@Suite("Budget changes for Undo (#25)")
struct BudgetChangeTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFixture  // swiftlint:disable:this type_name

    private let today = F.day(2026, 11, 20)

    private func make(_ budgets: [Budget] = []) throws -> (FakeBudgetRepository, DefaultBudgetUseCases) {
        let repository = FakeBudgetRepository(try B.saving([], budgets: budgets))
        return (repository, DefaultBudgetUseCases(repository: repository, now: { F.date(2026, 11, 5) }))
    }

    private func draft(
        _ name: String = "Eating out",
        limit: Decimal = 8_000,
        categories: [UUID] = [B.restaurantsID],
    ) -> BudgetDraft {
        BudgetDraft(
            name: name,
            limit: limit,
            currencyCode: "INR",
            categoryIDs: categories,
            startDay: F.day(2026, 11, 1),
        )
    }

    private func stored(_ repository: FakeBudgetRepository) throws -> [Budget] {
        try repository.budgets()
    }

    @Test("New Budget: Undo deletes it, Redo puts it back with the same ID and limit history")
    func newBudgetUndoRedo() throws {
        let (repository, useCases) = try make()
        let change = try useCases.savedChange(draft(), today: today)
        let saved = try #require(try stored(repository).first)
        #expect(change == .added(saved.id))

        let undo = try useCases.revert(change, expecting: try useCases.outcome(of: change))
        guard case .reverted(let redo, let redoOutcome) = undo else {
            Issue.record("Undo didn't revert: \(undo)")
            return
        }
        #expect(try stored(repository).isEmpty)
        #expect(redo == .removed(saved))
        #expect(redoOutcome.budget == nil)

        let again = try useCases.revert(redo, expecting: redoOutcome)
        guard case .reverted(let undoAgain, _) = again else {
            Issue.record("Redo didn't revert: \(again)")
            return
        }
        let restored = try #require(try stored(repository).first)
        #expect(restored.id == saved.id)
        #expect(restored.hasSameSettings(as: saved))
        #expect(restored.limits.map(\.id) == saved.limits.map(\.id))
        #expect(undoAgain == .added(saved.id))
    }

    @Test("Edit Budget: Undo saves the earlier version back, limit history included; Redo the edit again")
    func editUndoRedo() throws {
        let original = B.budget()
        let (repository, useCases) = try make([original])
        var edit = BudgetDraft(editing: original, today: today)
        edit.name = "Dining"
        edit.limit = 9_000
        let change = try useCases.savedChange(edit, today: today)
        guard case .replaced(let previous) = change else {
            Issue.record("Not a replace: \(change)")
            return
        }
        #expect(previous.hasSameSettings(as: original))
        let edited = try #require(try stored(repository).first)
        #expect(edited.name == "Dining")

        let undo = try useCases.revert(change, expecting: try useCases.outcome(of: change))
        guard case .reverted(let redo, let redoOutcome) = undo else {
            Issue.record("Undo didn't revert: \(undo)")
            return
        }
        let back = try #require(try stored(repository).first)
        #expect(back.hasSameSettings(as: original))
        #expect(back.limits.count == 1)

        _ = try useCases.revert(redo, expecting: redoOutcome)
        #expect(try stored(repository).first?.hasSameSettings(as: edited) == true)
    }

    @Test("Change Budget Limit: the change keeps the version before it for Undo (#25 AC 4)")
    func limitChange() throws {
        let original = B.budget(from: F.day(2026, 9, 1))
        let (repository, useCases) = try make([original])
        let change = try useCases.limitChange(of: original.id, to: 6_000, today: today)
        #expect(try stored(repository).first?.limits.count == 2)
        _ = try useCases.revert(change, expecting: try useCases.outcome(of: change))
        let back = try #require(try stored(repository).first)
        #expect(back.hasSameSettings(as: original))
    }

    @Test("D307.8: a budget changed since the step is stale, and nothing is written")
    func staleChanged() throws {
        let (repository, useCases) = try make()
        let change = try useCases.savedChange(draft(), today: today)
        let outcome = try useCases.outcome(of: change)
        var other = try #require(try stored(repository).first)
        other.carriesOverUnspent = true
        try repository.saveBudget(other)
        #expect(try useCases.revert(change, expecting: outcome) == .stale(.budgetChanged))
        #expect(try stored(repository).first?.carriesOverUnspent == true)
    }

    @Test("D307.8: a budget deleted since the step is stale")
    func staleDeleted() throws {
        let original = B.budget()
        let (repository, useCases) = try make([original])
        var edit = BudgetDraft(editing: original, today: today)
        edit.name = "Dining"
        let change = try useCases.savedChange(edit, today: today)
        let outcome = try useCases.outcome(of: change)
        try repository.deleteBudget(id: original.id)
        #expect(try useCases.revert(change, expecting: outcome) == .stale(.budgetDeleted))
        #expect(try stored(repository).isEmpty)
    }

    @Test("D307.8: Redo of a new budget that's back since then is stale")
    func staleRedoBack() throws {
        let (repository, useCases) = try make()
        let change = try useCases.savedChange(draft(), today: today)
        guard
            case .reverted(let redo, let redoOutcome) = try useCases.revert(
                change,
                expecting: try useCases.outcome(of: change),
            )
        else {
            Issue.record("Undo didn't revert")
            return
        }
        guard case .removed(let budget) = redo else {
            Issue.record("Not a removal: \(redo)")
            return
        }
        try repository.saveBudget(budget)
        #expect(try useCases.revert(redo, expecting: redoOutcome) == .stale(.budgetChanged))
    }

    @Test("D307.8, D306: a revert that would put back a deleted category is stale and names the category")
    func staleCategory() throws {
        let original = B.budget(categories: [B.restaurantsID, B.shoppingID])
        let (repository, useCases) = try make([original])
        var edit = BudgetDraft(editing: original, today: today)
        edit.categoryIDs = [B.restaurantsID]
        let change = try useCases.savedChange(edit, today: today)
        let outcome = try useCases.outcome(of: change)
        try repository.deletingCategory(B.shoppingID)
        #expect(try useCases.revert(change, expecting: outcome) == .stale(.categoryDeleted(B.shoppingID)))
        #expect(try stored(repository).first?.categoryIDs == [B.restaurantsID])
    }

    @Test("Another budget's change doesn't make the step stale")
    func otherBudgetIgnored() throws {
        let (repository, useCases) = try make([B.budget("Shopping", categories: [B.shoppingID])])
        let change = try useCases.savedChange(draft(), today: today)
        let outcome = try useCases.outcome(of: change)
        var other = try #require(try stored(repository).first { $0.name == "Shopping" })
        other.name = "Shopping trips"
        try repository.saveBudget(other)
        guard case .reverted = try useCases.revert(change, expecting: outcome) else {
            Issue.record("Stale for another budget's change")
            return
        }
        #expect(try stored(repository).map(\.name) == ["Shopping trips"])
    }

    @Test("D310.1: Redo of a new budget whose name another budget took since is stale, and nothing is written")
    func staleNameTakenRedo() throws {
        let (repository, useCases) = try make()
        let change = try useCases.savedChange(draft(), today: today)
        guard
            case .reverted(let redo, let redoOutcome) = try useCases.revert(
                change,
                expecting: try useCases.outcome(of: change),
            )
        else {
            Issue.record("Undo didn't revert")
            return
        }
        try repository.saveBudget(B.budget(" eating OUT ", categories: [B.shoppingID]))
        let before = repository.snapshot
        #expect(try useCases.revert(redo, expecting: redoOutcome) == .stale(.nameTaken("eating OUT")))
        #expect(repository.snapshot == before, "A stale step writes nothing")
    }

    @Test("D310.1: Undo of a rename whose old name another budget took since is stale, and nothing is written")
    func staleNameTakenUndo() throws {
        let original = B.budget("Eating out")
        let (repository, useCases) = try make([original])
        var edit = BudgetDraft(editing: original, today: today)
        edit.name = "Dining"
        let change = try useCases.savedChange(edit, today: today)
        let outcome = try useCases.outcome(of: change)
        try repository.saveBudget(B.budget("Eating Out", categories: [B.shoppingID]))
        let before = repository.snapshot
        #expect(try useCases.revert(change, expecting: outcome) == .stale(.nameTaken("Eating Out")))
        #expect(repository.snapshot == before)
    }

    @Test("D310.2: Undo puts back a version with no categories exactly, and Redo the edit again")
    func noCategoriesRestoresExactly() throws {
        let original = B.budget(categories: [B.travelID])
        let (repository, useCases) = try make([original])
        try repository.deletingCategory(B.travelID)
        let emptied = try #require(try stored(repository).first)
        #expect(emptied.categoryIDs.isEmpty, "D307.5 keeps the budget with no categories")
        var edit = BudgetDraft(editing: emptied, today: today)
        edit.categoryIDs = [B.restaurantsID]
        let change = try useCases.savedChange(edit, today: today)

        let undo = try useCases.revert(change, expecting: try useCases.outcome(of: change))
        guard case .reverted(let redo, let redoOutcome) = undo else {
            Issue.record("Undo didn't revert: \(undo)")
            return
        }
        let back = try #require(try stored(repository).first)
        #expect(back.categoryIDs.isEmpty)
        #expect(back.hasSameSettings(as: emptied))
        #expect(back.limits.map(\.id) == emptied.limits.map(\.id))

        guard case .reverted = try useCases.revert(redo, expecting: redoOutcome) else {
            Issue.record("Redo didn't revert")
            return
        }
        #expect(try stored(repository).first?.categoryIDs == [B.restaurantsID])
    }

    @Test("A write that fails throws and writes nothing, so the step can be tried again")
    func failedWrite() throws {
        let (repository, useCases) = try make()
        let change = try useCases.savedChange(draft(), today: today)
        let outcome = try useCases.outcome(of: change)
        repository.failsWrites = true
        #expect(throws: FakeBudgetRepository.WriteFailure.self) {
            try useCases.revert(change, expecting: outcome)
        }
        #expect(try stored(repository).count == 1)
        repository.failsWrites = false
        guard case .reverted = try useCases.revert(change, expecting: outcome) else {
            Issue.record("The retry didn't revert")
            return
        }
        #expect(try stored(repository).isEmpty)
    }

    @Test("NB3: a save whose read-back fails is still a change, not an error")
    func savedWithoutReadBack() throws {
        let original = B.budget()
        let (repository, useCases) = try make([original])
        let change = try useCases.savedChange(draft("Dining", categories: [B.shoppingID]), today: today)
        repository.failsReads = true
        #expect(throws: FakeBudgetRepository.ReadFailure.self) { try useCases.outcome(of: change) }
        repository.failsReads = false
        #expect(try stored(repository).map(\.name).sorted() == ["Dining", "Eating out"])
    }

    @Test("D307.7: changing the start or repeat of a budget with past periods asks first")
    func recalculation() {
        let started = B.budget(from: F.day(2026, 9, 1))
        var draft = BudgetDraft(editing: started, today: today)
        #expect(!draft.recalculatesPastPeriods(of: started, today: today))
        draft.limit = 1
        draft.name = "Other"
        #expect(!draft.recalculatesPastPeriods(of: started, today: today), "Other fields don't ask")
        draft.startDay = F.day(2026, 9, 2)
        #expect(draft.recalculatesPastPeriods(of: started, today: today))
        draft.startDay = started.startDay
        draft.recurrence = .custom(every: 3, unit: .week)
        #expect(draft.recalculatesPastPeriods(of: started, today: today))
    }

    @Test("D307.7: a budget with no past periods, or a new one, saves without asking")
    func noRecalculation() {
        let current = B.budget(from: F.day(2026, 11, 1))
        var draft = BudgetDraft(editing: current, today: today)
        draft.startDay = F.day(2026, 11, 5)
        #expect(!current.hasPastPeriods(today: today))
        #expect(!draft.recalculatesPastPeriods(of: current, today: today))
        let future = B.budget(from: F.day(2027, 1, 1))
        var later = BudgetDraft(editing: future, today: today)
        later.recurrence = .weekly
        #expect(!later.recalculatesPastPeriods(of: future, today: today))
        var new = BudgetDraft(currencyCode: "INR", startDay: F.day(2026, 1, 1))
        new.recurrence = .weekly
        #expect(!new.recalculatesPastPeriods(of: B.budget(from: F.day(2026, 1, 1)), today: today))
    }

    @Test("Same settings compares the values a user sets, not bookkeeping dates or IDs")
    func sameSettings() {
        let budget = B.budget()
        var copy = budget
        copy.updatedAt = F.date(2027, 1, 1)
        copy.limits = copy.limits.map { BudgetLimit(startDay: $0.startDay, amount: $0.amount) }
        copy.categoryIDs = copy.categoryIDs.reversed()
        #expect(budget.hasSameSettings(as: copy))
        copy.limits[0].amount = 1
        #expect(!budget.hasSameSettings(as: copy))
    }
}

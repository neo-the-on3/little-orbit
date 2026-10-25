import Foundation
import LittleOrbitDomain
import Testing

/// Deleting a budget as a revertible change (D307.8 Delete Budget), including one with no categories left (D307.5,
/// D310.2) and one whose name another budget took meanwhile (D310.1).
@MainActor
@Suite("Budget delete for Undo (#25)")
struct BudgetDeleteChangeTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFixture  // swiftlint:disable:this type_name

    private let today = F.day(2026, 11, 20)

    @Test("Delete Budget: Undo puts it back with the same ID and limit history; Redo deletes it again")
    func deleteUndoRedo() throws {
        let budget = B.budget()
        let repository = FakeBudgetRepository(try B.saving([], budgets: [budget]))
        let useCases = DefaultBudgetUseCases(repository: repository, now: { F.date(2026, 11, 5) })
        try useCases.changeLimit(of: budget.id, to: 9_000, today: F.day(2027, 1, 10))
        let stored = try #require(try repository.budgets().first)

        let change = try useCases.deletedChange(of: budget.id)
        #expect(change == .removed(stored))
        #expect(try repository.budgets().isEmpty)

        let undo = try useCases.revert(change, expecting: try useCases.outcome(of: change))
        guard case .reverted(let redo, let redoOutcome) = undo else {
            Issue.record("Undo didn't revert: \(undo)")
            return
        }
        let back = try #require(try repository.budgets().first)
        #expect(back.id == budget.id)
        #expect(back.hasSameSettings(as: stored))
        #expect(back.limits.count == 2)

        let again = try useCases.revert(redo, expecting: redoOutcome)
        guard case .reverted = again else {
            Issue.record("Redo didn't revert: \(again)")
            return
        }
        #expect(try repository.budgets().isEmpty)
    }

    @Test("D310.2: Undo Delete Budget puts back a budget with no categories left, exactly")
    func undoDeleteWithNoCategories() throws {
        let budget = B.budget(categories: [B.travelID])
        let repository = FakeBudgetRepository(try B.saving([], budgets: [budget]))
        try repository.deletingCategory(B.travelID)
        let useCases = DefaultBudgetUseCases(repository: repository, now: { F.date(2026, 11, 5) })
        #expect(try useCases.summary(of: budget.id, today: today).hasNoCategories)

        let change = try useCases.deletedChange(of: budget.id)
        let undo = try useCases.revert(change, expecting: try useCases.outcome(of: change))
        guard case .reverted = undo else {
            Issue.record("Undo didn't revert: \(undo)")
            return
        }
        #expect(try repository.budgets().map(\.id) == [budget.id])
        #expect(try repository.budgets().first?.categoryIDs.isEmpty == true)
    }

    @Test("D310.1: Undo Delete Budget when another budget took the name is stale, and nothing is written")
    func undoDeleteNameTaken() throws {
        let budget = B.budget()
        let repository = FakeBudgetRepository(try B.saving([], budgets: [budget]))
        let useCases = DefaultBudgetUseCases(repository: repository, now: { F.date(2026, 11, 5) })
        let change = try useCases.deletedChange(of: budget.id)
        let outcome = try useCases.outcome(of: change)
        try repository.saveBudget(B.budget("EATING OUT"))
        let before = repository.snapshot
        #expect(try useCases.revert(change, expecting: outcome) == .stale(.nameTaken("EATING OUT")))
        #expect(repository.snapshot == before, "A stale step writes nothing")
    }

    @Test("Deleting a budget that's already gone throws missingBudget")
    func deleteMissing() throws {
        let useCases = DefaultBudgetUseCases(repository: FakeBudgetRepository(), now: { F.date(2026, 11, 5) })
        #expect(throws: LedgerValidationError.missingBudget) {
            try useCases.deletedChange(of: UUID())
        }
    }
}

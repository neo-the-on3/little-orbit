import Foundation
import LittleOrbitDomain

/// A budget save, a limit change, a delete or a Mac duplicate as one step of the window's Undo history (D307.8).
/// Undo and Redo keep the user's action as its name, with the budget's name after the step: “New Budget Eating
/// out”, “Edit Budget Eating out”, “Change Budget Limit Eating out” or “Duplicate Budget Eating out copy”. A stale step says “Eating out has changed since then.
/// Nothing was changed.”, “Eating out has been deleted. …”, for a category it would put back, “Groceries has
/// been deleted. …” (D228.5, the D306 amendment), or, for a name another budget took since, “There’s already a
/// budget named “Eating out”. Nothing was changed.” (D310.1).
@MainActor
struct BudgetUndoStep: RecordUndoChange {
    /// What the user did, for the step's name.
    enum Action: Equatable, Sendable {
        case new
        case edit
        case changeLimit
        /// Delete Budget, from the budget detail (#25 part 4).
        case delete
        /// Duplicate Budget, on the Mac (#25 part 5, D307.6). The step is named after the copy.
        case duplicate
    }

    let name: String
    let budgetName: String
    let change: BudgetChange
    let outcome: BudgetChangeOutcome
    let changes: any BudgetChangesUseCase
    /// Names of the categories the step could put back, for the stale message about a deleted one.
    let categoryNames: [UUID: String]

    /// The step for a change just made, or `nil` when what it left can't be read back, so it couldn't be
    /// checked and isn't kept (D187.5). Without `budgetName` it's named after the budget the change left, such as
    /// a duplicate's copy.
    static func make(
        _ change: BudgetChange,
        action: Action,
        budgetName: String?,
        categoryNames: [UUID: String],
        changes: any BudgetChangesUseCase,
    ) -> BudgetUndoStep? {
        guard let outcome = try? changes.outcome(of: change),
            let budgetName = budgetName ?? outcome.budget?.name
        else {
            return nil
        }
        return BudgetUndoStep(
            name: BudgetText.undoName(action, budgetName),
            budgetName: budgetName,
            change: change,
            outcome: outcome,
            changes: changes,
            categoryNames: categoryNames,
        )
    }

    func revert() throws -> RecordRevertResult {
        switch try changes.revert(change, expecting: outcome) {
        case .reverted(let inverse, let outcome):
            .reverted(
                BudgetUndoStep(
                    name: name,
                    budgetName: budgetName,
                    change: inverse,
                    outcome: outcome,
                    changes: changes,
                    categoryNames: categoryNames,
                )
            )
        case .stale(.budgetChanged):
            .stale(message: StaleText.changed(budgetName))
        case .stale(.budgetDeleted):
            .stale(message: StaleText.deleted(budgetName))
        case .stale(.categoryDeleted(let id)):
            .stale(message: categoryNames[id].map(StaleText.deleted) ?? BudgetText.categoryDeleted)
        case .stale(.nameTaken(let otherName)):
            .stale(message: BudgetText.nameTaken(otherName))
        }
    }
}

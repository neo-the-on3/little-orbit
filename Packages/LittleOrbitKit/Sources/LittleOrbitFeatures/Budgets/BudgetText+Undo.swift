import Foundation

// The budget Undo and Redo names (D307.8). Each is one catalog entry with the budget's name after the step.
extension BudgetText {
    static func undoName(_ action: BudgetUndoStep.Action, _ name: String) -> String {
        switch action {
        case .new: FeatureText.format("New Budget %@", name)
        case .edit: FeatureText.format("Edit Budget %@", name)
        case .changeLimit: FeatureText.format("Change Budget Limit %@", name)
        case .delete: FeatureText.format("Delete Budget %@", name)
        case .duplicate: FeatureText.format("Duplicate Budget %@", name)
        }
    }

    /// The stale message when a deleted category's name isn't known (D309.7).
    static var categoryDeleted: String {
        FeatureText.string(
            "A category has been deleted. Nothing was changed.",
            comment:
                "Alert message under “Can’t Undo …” or “Can’t Redo …”: the step would put back a category that has been deleted since, and its name isn’t known. Don’t name a cause.",
        )
    }

    /// “There’s already a budget named “Eating out”. Nothing was changed.”: Undo or Redo would give the budget a
    /// name another budget has taken since, so the step is stale (D310.1).
    static func nameTaken(_ name: String) -> String {
        FeatureText.format("There’s already a budget named “%@”. Nothing was changed.", name)
    }
}

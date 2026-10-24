import Foundation
import LittleOrbitDomain

/// The wording of the transaction form's category picker (#24 frames 16:7540 and 16:7702), from the
/// package's String Catalog. Cancel, Done, Archived and the alerts reuse the category screens' entries.
enum CategoryPickerText {
    static var title: String {
        FeatureText.string("Category", comment: "Transaction form: the category picker’s title.")
    }

    static var searchPrompt: String {
        FeatureText.string(
            "Search or create",
            comment:
                "Transaction form category picker: the search field’s placeholder. Typing a new name offers to create it.",
        )
    }

    static var uncategorised: String {
        FeatureText.string(
            "Uncategorised",
            comment: "Transaction form category picker: the row that saves the transaction without a category.",
        )
    }

    static var noCategory: String {
        FeatureText.string(
            "No category",
            comment: "Transaction form category picker: the subtitle under “Uncategorised”.",
        )
    }

    /// “Create “Pet care””: the row that adds the typed name as a new top-level category.
    static func create(_ name: String) -> String {
        FeatureText.string(
            "Create “\(name)”",
            comment:
                "Transaction form category picker: adds the typed name as a new category. %@ is the name typed, trimmed.",
        )
    }

    /// “Expense category”, beside the Create row: the kind the new category takes from the transaction.
    static func newKind(_ kind: CategoryKind) -> String {
        switch kind {
        case .expense:
            FeatureText.string(
                "Expense category",
                comment: "Transaction form category picker, beside the Create row on an expense: what it creates.",
            )
        case .income:
            FeatureText.string(
                "Income category",
                comment: "Transaction form category picker, beside the Create row on an income: what it creates.",
            )
        }
    }
}

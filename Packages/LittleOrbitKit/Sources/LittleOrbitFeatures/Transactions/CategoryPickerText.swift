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
            comment:
                "The row for no category: in the transaction form's category picker it saves the transaction without one; in the spending report it's the row, and its drill-down's title, for spending with no category.",
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

    /// Under the Create row when an archived category already has the typed name (D303), quoting its stored
    /// name.
    static func archivedName(_ name: String) -> String {
        FeatureText.string(
            "There’s an archived category named “\(name)”. Unarchive it in Categories to use it.",
            comment:
                "Transaction form category picker, under the Create row: an archived top-level category of the same kind has the typed name, ignoring case and spaces, so it can’t be created. %@ is the archived category’s name as stored.",
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

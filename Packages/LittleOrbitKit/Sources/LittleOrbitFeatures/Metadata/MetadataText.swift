import Foundation
import LittleOrbitDomain

/// The wording of the Mac Metadata manager (#24 part 5), from the package's String Catalog. Words the iOS
/// category screens already use, such as Cancel, Save, the editor's footnotes and the merge footnote's
/// sentences, are the same entries.
enum MetadataText {
    // MARK: Window

    static var windowTitle: String {
        FeatureText.string(
            "Metadata",
            comment: "Mac: the Metadata manager window’s title, and the app menu item that opens it.",
        )
    }

    static var add: String {
        FeatureText.string("Add", comment: "Mac Metadata manager toolbar: the menu of things to add.")
    }

    static func addCategory(_ kind: CategoryKind) -> String {
        switch kind {
        case .expense:
            FeatureText.string(
                "Add Expense Category",
                comment: "Mac Metadata manager, Add menu: adds a top-level expense category.",
            )
        case .income:
            FeatureText.string(
                "Add Income Category",
                comment: "Mac Metadata manager, Add menu: adds a top-level income category.",
            )
        }
    }

    static var rename: String {
        FeatureText.string(
            "Rename",
            comment:
                "Mac Metadata manager, a category or payee row’s context menu: edit the name in the row (Return saves, Esc cancels).",
        )
    }

    static func editCategory(isSubcategory: Bool) -> String {
        isSubcategory
            ? FeatureText.string(
                "Edit Subcategory…",
                comment: "Mac Metadata manager, a row’s context menu: opens the Edit Subcategory sheet.",
            )
            : FeatureText.string(
                "Edit Category…",
                comment: "Mac Metadata manager, a row’s context menu: opens the Edit Category sheet.",
            )
    }

    // MARK: Table

    static var usedColumn: String {
        FeatureText.string(
            "Used",
            comment: "Mac Metadata manager: the column with how many transactions use each category or payee.",
        )
    }

    /// "2 selected · 1 expense, 1 income": both kinds are selected, so Merge is off.
    static func mixedSelection(_ selected: String, expenses: Int, income: Int) -> String {
        FeatureText.format("%1$@ · %2$lld expense, %3$lld income", selected, expenses, income)
    }

    /// The status bar while a row is renamed. Top-level names are unique within their kind and subcategory
    /// names within their parent (D299, D304.7).
    static func renameHint(isSubcategory: Bool) -> String {
        isSubcategory
            ? FeatureText.string(
                "Return saves · Esc cancels · names must be unique within the same parent",
                comment: "Mac Metadata manager status bar while a subcategory is being renamed in its row.",
            )
            : FeatureText.string(
                "Return saves · Esc cancels · names must be unique among categories of the same kind",
                comment:
                    "Mac Metadata manager status bar while a top-level category is being renamed in its row; an expense and an income category may share a name.",
            )
    }

    // MARK: Merge

    static var mixedKindsHelp: String {
        FeatureText.string(
            "Merge is only available for categories of the same kind.",
            comment:
                "Mac Metadata manager: the tooltip on the disabled Merge button when an expense and an income category are selected.",
        )
    }

    static var selectTwoHelp: String {
        FeatureText.string(
            "Select two categories of the same kind to merge.",
            comment:
                "Mac Metadata manager: the tooltip on the disabled Merge button when fewer or more than two categories are selected.",
        )
    }

    /// "Merge 2 Categories".
    static func mergeTitle(_ count: Int) -> String {
        FeatureText.plural("Merge %lld Categories", one: "Merge %lld Category", count)
    }

    /// "Food & Dining and Groceries are both expense categories. Choose the one to keep; …"
    static func mergeMessage(_ first: String, _ second: String, kind: CategoryKind) -> String {
        switch kind {
        case .expense:
            FeatureText.format(
                "%1$@ and %2$@ are both expense categories. Choose the one to keep; the other’s transactions move to it and it is deleted.",
                first,
                second,
            )
        case .income:
            FeatureText.format(
                "%1$@ and %2$@ are both income categories. Choose the one to keep; the other’s transactions move to it and it is deleted.",
                first,
                second,
            )
        }
    }

    static var keep: String {
        FeatureText.string(
            "Keep:",
            comment: "Mac Merge Categories sheet: the pop-up button’s label, choosing the category that’s kept.",
        )
    }

    // MARK: Editor sheet

    static var nameLabel: String {
        FeatureText.string("Name:", comment: "Mac category editor sheet: the name field’s label.")
    }

    static var kindLabel: String {
        FeatureText.string("Kind:", comment: "Mac category editor sheet: the label of the read-only kind.")
    }

    static var parentLabel: String {
        FeatureText.string(
            "Parent:",
            comment: "Mac category editor sheet: the label of a subcategory’s read-only parent.",
        )
    }

    static var iconLabel: String {
        FeatureText.string("Icon:", comment: "Mac category editor sheet: the label of the icon pop-up button.")
    }

    static var colourLabel: String {
        FeatureText.string("Colour:", comment: "Mac category editor sheet: the label of the colour pop-up button.")
    }

    static var iconFootnote: String {
        FeatureText.string(
            "An icon saved by an earlier version that isn’t in this list shows first as “Current Icon”. Each name is the icon’s VoiceOver label.",
            comment: "Mac category editor: the footnote under the icon popover’s grid.",
        )
    }
}

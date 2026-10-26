import Foundation
import LittleOrbitDomain

/// The wording of the iOS Settings › Categories screens (#24), from the package's String Catalog. Long
/// messages are whole sentences, each its own entry, joined with the catalog's "%1$@ %2$@" (D287.3).
enum CategoryText {
    // MARK: List

    static var title: String {
        FeatureText.string("Categories", comment: "Settings row and screen title: the category manager.")
    }

    static func kindName(_ kind: CategoryKind) -> String {
        switch kind {
        case .expense:
            FeatureText.string("Expense", comment: "A category's kind, and the Categories screen's Expense tab.")
        case .income:
            FeatureText.string("Income", comment: "A category's kind, and the Categories screen's Income tab.")
        }
    }

    static var kindPicker: String {
        FeatureText.string("Kind", comment: "Categories screen: the Expense or Income picker, and the editor’s row.")
    }

    /// "Expense · 25 transactions": the kind and what uses the category itself.
    static func usage(kind: CategoryKind, count: Int) -> String {
        FeatureText.pluralFormat(
            "%1$@ · %2$lld transactions",
            one: "%1$@ · %2$lld transaction",
            count: count,
            kindName(kind),
            count,
        )
    }

    /// "Expense · 2 subcategories": a top-level category that has subcategories.
    static func subcategories(kind: CategoryKind, count: Int) -> String {
        FeatureText.pluralFormat(
            "%1$@ · %2$lld subcategories",
            one: "%1$@ · %2$lld subcategory",
            count: count,
            kindName(kind),
            count,
        )
    }

    /// "Expense · 4 transactions · 1 subcategory": a top-level category with subcategories, counting only what
    /// uses the parent itself. A zero transaction count is left out (UI Designer's ruling on #155).
    static func parentSummary(kind: CategoryKind, count: Int, subcategoryCount: Int) -> String {
        guard count > 0 else {
            return subcategories(kind: kind, count: subcategoryCount)
        }
        #if canImport(Darwin)
            return FeatureText.format(
                "%1$@ · %2$lld transactions · %3$lld subcategories",
                kindName(kind),
                count,
                subcategoryCount,
            )
        #else
            // Linux has no catalog: the catalog's English, chosen here.
            let format =
                switch (count == 1, subcategoryCount == 1) {
                case (true, true): "%1$@ · %2$lld transaction · %3$lld subcategory"
                case (true, false): "%1$@ · %2$lld transaction · %3$lld subcategories"
                case (false, true): "%1$@ · %2$lld transactions · %3$lld subcategory"
                case (false, false): "%1$@ · %2$lld transactions · %3$lld subcategories"
                }
            return String(format: format, kindName(kind), count, subcategoryCount)
        #endif
    }

    static var listFooter: String {
        FeatureText.string(
            "Tap a category’s arrow to show its subcategories (one level). Archived categories stay out of pickers but keep their history in reports. Uncategorised isn’t a category: expenses and income without one show the gray ? chip; transfers never have a category.",
            comment: "Categories screen footer under the list.",
        )
    }

    static var reorderFooter: String {
        FeatureText.string(
            "Drag the handles to reorder. Subcategories reorder within their parent. A category with subcategories can’t move under another one.",
            comment: "Categories screen footer while reordering.",
        )
    }

    static var archived: String {
        FeatureText.string(
            "Archived",
            comment:
                "Categories screen: the section of archived categories. Transaction form category picker: the section with the transaction’s own archived category.",
        )
    }

    static var archivedFooter: String {
        FeatureText.string(
            "Unarchive puts a category back in pickers. Archived categories stay in reports.",
            comment: "Categories screen footer under the Archived section.",
        )
    }

    static var more: String {
        FeatureText.string("More", comment: "Categories screen: the toolbar menu’s accessibility label.")
    }

    static var addCategory: String {
        FeatureText.string("Add Category", comment: "Categories screen menu item: add a top-level category.")
    }

    static var addSubcategory: String {
        FeatureText.string("Add Subcategory", comment: "Categories screen menu item: add a subcategory.")
    }

    static var reorder: String {
        FeatureText.string("Reorder", comment: "Categories screen menu item: drag categories into a new order.")
    }

    static var done: String {
        FeatureText.string(
            "Done",
            comment:
                "Categories and Payees screens: ends reordering or selecting. Transaction form category picker: puts the checked category on the form.",
        )
    }

    static var cancel: String {
        FeatureText.string("Cancel", comment: "Category sheets and alerts: close without changing anything.")
    }

    static var okay: String {
        FeatureText.string("OK", comment: "Closes a category alert.")
    }

    // MARK: Editor

    static func editorTitle(isNew: Bool, isSubcategory: Bool) -> String {
        switch (isNew, isSubcategory) {
        case (true, false): FeatureText.string("New Category", comment: "Category editor title: adding.")
        case (true, true): FeatureText.string("New Subcategory", comment: "Category editor title: adding.")
        case (false, false): FeatureText.string("Edit Category", comment: "Category editor title: editing.")
        case (false, true): FeatureText.string("Edit Subcategory", comment: "Category editor title: editing.")
        }
    }

    static var name: String {
        FeatureText.string("Name", comment: "Category editor: the name field’s placeholder and VoiceOver label.")
    }

    static var details: String {
        FeatureText.string("Details", comment: "Category editor: the section header over Kind, Parent, Icon, Colour.")
    }

    /// "Expense (from parent)": a subcategory's kind, which it takes from its parent.
    static func kindFromParent(_ kind: CategoryKind) -> String {
        switch kind {
        case .expense:
            FeatureText.string("Expense (from parent)", comment: "Category editor: a subcategory’s fixed kind.")
        case .income:
            FeatureText.string("Income (from parent)", comment: "Category editor: a subcategory’s fixed kind.")
        }
    }

    static var parent: String {
        FeatureText.string("Parent", comment: "Category editor row: the subcategory’s parent category.")
    }

    static var icon: String {
        FeatureText.string("Icon", comment: "Category editor row: the category’s symbol.")
    }

    static var colour: String {
        FeatureText.string("Colour", comment: "Category editor row: the category’s colour.")
    }

    static var save: String {
        FeatureText.string("Save", comment: "Category editor: saves the category.")
    }

    static var subcategoryFootnote: String {
        FeatureText.string(
            "A subcategory always has its parent’s kind, so Kind can’t change. One level only: subcategories can’t have their own. Names must be unique within the same parent.",
            comment: "Category editor footnote for a subcategory.",
        )
    }

    static var categoryFootnote: String {
        FeatureText.string(
            "Kind comes from the tab it’s added on and can’t change later. Names must be unique among categories of the same kind.",
            comment: "Category editor footnote for a top-level category.",
        )
    }

    static var mergeInto: String {
        FeatureText.string("Merge into…", comment: "Category editor row: opens the Merge sheet.")
    }

    static func deleteRow(isSubcategory: Bool) -> String {
        isSubcategory
            ? FeatureText.string("Delete Subcategory…", comment: "Category editor: delete button.")
            : FeatureText.string("Delete Category…", comment: "Category editor: delete button.")
    }

    /// A category change that failed and left everything as it was (D295.5). OK only.
    static var couldntSaveTitle: String {
        FeatureText.string(
            "Couldn’t Save Changes",
            comment:
                "Alert title: a category, payee, scheduled item or transaction change couldn’t be saved and nothing changed. Its only button is OK.",
        )
    }

    static var emptyName: String {
        FeatureText.string(
            "Enter a name.",
            comment: "Category editor, under the name field: the name is empty or only spaces.",
        )
    }

    static var nameTooLong: String {
        FeatureText.string(
            "Use 100 characters or fewer.",
            comment: "Category editor, under the name field: the name is longer than 100 characters.",
        )
    }

    static func duplicateName(_ name: String) -> String {
        FeatureText.string(
            "There’s already a category named “\(name)” here.",
            comment:
                "Category editor, under the name field: another category at the same level (the same parent, or the same kind at the top level) has this name, ignoring case and spaces. The name typed.",
        )
    }

    static var nothingChanged: String {
        FeatureText.string(
            "Your categories weren’t changed. Try again.",
            comment: "Alert message: a category change failed and nothing was saved.",
        )
    }

    // MARK: Colours

    // One literal per hue, so each name is its own catalog entry.
    // swiftlint:disable:next cyclomatic_complexity
    static func colourName(_ hue: CategoryHue) -> String {
        switch hue {
        case .red: FeatureText.string("Red", comment: "Category colour name.")
        case .orange: FeatureText.string("Orange", comment: "Category colour name.")
        case .amber: FeatureText.string("Amber", comment: "Category colour name.")
        case .yellow: FeatureText.string("Yellow", comment: "Category colour name.")
        case .lime: FeatureText.string("Lime", comment: "Category colour name.")
        case .green: FeatureText.string("Green", comment: "Category colour name.")
        case .teal: FeatureText.string("Teal", comment: "Category colour name.")
        case .cyan: FeatureText.string("Cyan", comment: "Category colour name.")
        case .blue: FeatureText.string("Blue", comment: "Category colour name.")
        case .indigo: FeatureText.string("Indigo", comment: "Category colour name.")
        case .purple: FeatureText.string("Purple", comment: "Category colour name.")
        case .pink: FeatureText.string("Pink", comment: "Category colour name.")
        case .gray: FeatureText.string("Gray", comment: "Category colour name.")
        }
    }

    // MARK: Merge (D19, D287.3, D291.1)

    static func mergeTitle(_ name: String) -> String {
        FeatureText.string("Merge \(name)", comment: "Merge sheet title. The category being merged.")
    }

    static var merge: String {
        FeatureText.string("Merge", comment: "Merge sheet: merges the category into the chosen one.")
    }

    /// "Merge “Groceries” (25 transactions) into:"
    static func mergeHeader(name: String, count: Int) -> String {
        FeatureText.pluralFormat(
            "Merge “%1$@” (%2$lld transactions) into:",
            one: "Merge “%1$@” (%2$lld transaction) into:",
            count: count,
            name,
            count,
        )
    }

    /// "25 transactions will use Food & Dining."
    static func willUse(count: Int, target: String) -> String {
        FeatureText.pluralFormat(
            "%1$lld transactions will use %2$@.",
            one: "%1$lld transaction will use %2$@.",
            count: count,
            count,
            target,
        )
    }

    static func thenDeleted(_ name: String) -> String {
        FeatureText.string("\(name) is then deleted.", comment: "Merge sheet footnote sentence. The merged category.")
    }

    static func otherKindNotListed(_ kind: CategoryKind) -> String {
        switch kind {
        case .expense:
            FeatureText.string(
                "Income categories can’t be merged with expense ones, so they aren’t listed.",
                comment: "Merge sheet footnote sentence, merging an expense category.",
            )
        case .income:
            FeatureText.string(
                "Expense categories can’t be merged with income ones, so they aren’t listed.",
                comment: "Merge sheet footnote sentence, merging an income category.",
            )
        }
    }

    /// "Its 2 subcategories move to “Food & Dining”." (D301), before “Merging can’t be undone.”
    static func subcategoriesMove(count: Int, to target: String) -> String {
        #if !canImport(Darwin)
            // Linux's `String(format:)` can't skip the count (%1$lld) that the singular leaves out.
            if count == 1 {
                return String(format: "Its subcategory moves to “%@”.", target)
            }
        #endif
        return FeatureText.pluralFormat(
            "Its %1$lld subcategories move to “%2$@”.",
            one: "Its subcategory moves to “%2$@”.",
            count: count,
            count,
            target,
        )
    }

    static var mergingCantBeUndone: String {
        FeatureText.string("Merging can’t be undone.", comment: "Last sentence of the Merge sheet footnote (D287.3).")
    }

    static var cantMergeTitle: String {
        FeatureText.string(
            "Can’t Merge Categories",
            comment: "Alert title: a merge would put two subcategories with the same name under one parent (D291.1).",
        )
    }

    /// D291.1: "“Leisure” and “Entertainment” both have a subcategory named “Movies”. Rename or merge one of
    /// them first."
    static func mergeClash(source: String, survivor: String, count: Int, firstName: String) -> String {
        #if !canImport(Darwin)
            // Linux's `String(format:)` can't skip the count (%3$lld) that the singular leaves out, so the
            // English singular gets its names in order there. Apple platforms read the catalog's plural.
            if count == 1 {
                return String(
                    format:
                        "“%1$@” and “%2$@” both have a subcategory named “%3$@”. Rename or merge one of them first.",
                    source,
                    survivor,
                    firstName,
                )
            }
        #endif
        return FeatureText.pluralFormat(
            "“%1$@” and “%2$@” both have subcategories with %3$lld of the same names, including “%4$@”. Rename or merge one of each pair first.",
            one: "“%1$@” and “%2$@” both have a subcategory named “%4$@”. Rename or merge one of them first.",
            count: count,
            source,
            survivor,
            count,
            firstName,
        )
    }

    // MARK: Joining

    /// Two sentences in a row, with the catalog's "%1$@ %2$@".
    static func sentences(_ parts: [String]) -> String {
        parts.dropFirst()
            .reduce(parts.first ?? "") { joined, next in
                FeatureText.format("%1$@ %2$@", joined, next)
            }
    }

    /// "Groceries and Restaurants", in the user's language where the platform can.
    static func list(_ names: [String]) -> String {
        #if canImport(Darwin)
            names.formatted(.list(type: .and))
        #else
            switch names.count {
            case 0: ""
            case 1: names[0]
            default: names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
            }
        #endif
    }
}

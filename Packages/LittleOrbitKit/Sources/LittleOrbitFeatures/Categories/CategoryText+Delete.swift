import Foundation
import LittleOrbitDomain

// The delete alert and Move To sheet text, apart from `CategoryText` to keep each file short.
extension CategoryText {
    // MARK: Delete (D19, D287.3)

    static func deleteTitle(_ name: String) -> String {
        FeatureText.string("Delete “\(name)”?", comment: "Category delete alert title. The category’s name.")
    }

    static var archiveCategory: String {
        FeatureText.string("Archive Category", comment: "Category delete alert: the default, safe choice (D19).")
    }

    static var moveToAnother: String {
        FeatureText.string(
            "Move to Another Category…",
            comment: "Category delete alert: move its transactions, then delete it.",
        )
    }

    static var leaveUncategorised: String {
        FeatureText.string(
            "Delete, Leave Uncategorised",
            comment: "Category delete alert: delete it and leave its transactions with no category.",
        )
    }

    static var delete: String {
        FeatureText.string("Delete", comment: "Delete alert for a category nothing uses.")
    }

    /// "It’s used by 385 transactions, including those in Groceries and Restaurants."
    static func usedBy(_ count: Int, subcategoryNames: [String]) -> String {
        if subcategoryNames.isEmpty {
            return FeatureText.plural(
                "It’s used by %lld transactions.",
                one: "It’s used by %lld transaction.",
                count,
            )
        }
        return FeatureText.pluralFormat(
            "It’s used by %1$lld transactions, including those in %2$@.",
            one: "It’s used by %1$lld transaction, in %2$@.",
            count: count,
            count,
            list(subcategoryNames),
        )
    }

    static var archiveKeepsHistory: String {
        FeatureText.string(
            "Archive hides it from pickers and keeps its history.",
            comment: "Category delete alert sentence, after what uses the category.",
        )
    }

    /// "Moving or leaving them uncategorised deletes the category and its 2 subcategories." `count`, what uses
    /// it, picks “it” or “them” (D301); each count has its own plural in the catalog. One subcategory reads “and
    /// its subcategory”, with no number (UI Designer).
    static func movingDeletes(count: Int, subcategoryCount: Int) -> String {
        #if canImport(Darwin)
            if subcategoryCount == 0 {
                return FeatureText.format("category.delete.movingDeletes", count)
            }
            return FeatureText.format("category.delete.movingDeletesWithSubcategories", count, subcategoryCount)
        #else
            // Linux has no catalog: the catalog's English, chosen here.
            switch (count == 1, subcategoryCount) {
            case (true, 0):
                return "Moving or leaving it uncategorised deletes the category."
            case (false, 0):
                return "Moving or leaving them uncategorised deletes the category."
            case (true, 1):
                return "Moving or leaving it uncategorised deletes the category and its subcategory."
            case (false, 1):
                return "Moving or leaving them uncategorised deletes the category and its subcategory."
            case (true, _):
                return String(
                    format: "Moving or leaving it uncategorised deletes the category and its %lld subcategories.",
                    subcategoryCount,
                )
            case (false, _):
                return String(
                    format: "Moving or leaving them uncategorised deletes the category and its %lld subcategories.",
                    subcategoryCount,
                )
            }
        #endif
    }

    static var nothingUses: String {
        FeatureText.string(
            "Nothing uses it.",
            comment: "Delete alert sentence for a category no transaction or split line uses.",
        )
    }

    static func deletesSubcategoriesToo(_ count: Int) -> String {
        FeatureText.plural(
            "Its %lld subcategories are deleted too.",
            one: "Its subcategory is deleted too.",
            count,
        )
    }

    static var deletingCantBeUndone: String {
        FeatureText.string(
            "Deleting can’t be undone.",
            comment: "Last sentence of the category delete alerts (D287.3).",
        )
    }

    // MARK: Move To (delete)

    static var moveToTitle: String {
        FeatureText.string("Move To", comment: "Sheet title: choose where a deleted category’s transactions go.")
    }

    static var move: String {
        FeatureText.string("Move", comment: "Move To sheet: moves the transactions and deletes the category.")
    }

    /// "Move 385 transactions from Food & Dining and its subcategories to:"
    static func moveHeader(count: Int, name: String, hasSubcategories: Bool) -> String {
        if hasSubcategories {
            return FeatureText.pluralFormat(
                "Move %1$lld transactions from %2$@ and its subcategories to:",
                one: "Move %1$lld transaction from %2$@ and its subcategories to:",
                count: count,
                count,
                name,
            )
        }
        return FeatureText.pluralFormat(
            "Move %1$lld transactions from %2$@ to:",
            one: "Move %1$lld transaction from %2$@ to:",
            count: count,
            count,
            name,
        )
    }

    static func onlyKindOffered(_ kind: CategoryKind) -> String {
        switch kind {
        case .expense:
            FeatureText.string("Only expense categories are offered.", comment: "Move To sheet footer sentence.")
        case .income:
            FeatureText.string("Only income categories are offered.", comment: "Move To sheet footer sentence.")
        }
    }

    /// "Food & Dining, Groceries and Restaurants are deleted after the move."
    static func deletedAfterMove(_ names: [String]) -> String {
        if names.count == 1 {
            return FeatureText.string(
                "\(names[0]) is deleted after the move.",
                comment: "Move To sheet footer sentence. The category’s name.",
            )
        }
        return FeatureText.string(
            "\(list(names)) are deleted after the move.",
            comment: "Move To sheet footer sentence. The category and its subcategories, as a list.",
        )
    }
}

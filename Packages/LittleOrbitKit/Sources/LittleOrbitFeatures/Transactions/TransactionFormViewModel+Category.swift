import Foundation
import LittleOrbitDomain

// The entry sheet's Category and Payee rows (#23): the category choices and payee autocomplete. Everything
// here reads the ledger the sheet loaded when it opened.
extension TransactionFormViewModel {
    public var categoryOptions: [TransactionCategoryOption] {
        guard type != .transfer else {
            return []
        }
        let fitting = categories.filter { !$0.isArchived && $0.deletedAt == nil && $0.kind.matches(type) }
        let parents = fitting.filter { $0.parentID == nil }.sorted { $0.sortOrder < $1.sortOrder }
        return parents.flatMap { parent in
            let children = fitting.filter { $0.parentID == parent.id }.sorted { $0.sortOrder < $1.sortOrder }
            return ([parent] + children)
                .map { category in
                    TransactionCategoryOption(
                        id: category.id,
                        name: category.name,
                        symbolName: category.iconName ?? "tag",
                        isSubcategory: category.parentID != nil,
                        parentID: category.parentID,
                    )
                }
        }
    }

    /// The category picker's sections: each parent, then its subcategories.
    public var categoryGroups: [TransactionCategoryGroup] {
        TransactionCategoryGroup.groups(categoryOptions)
    }

    public var categoryName: String {
        categories.first { $0.id == categoryID }?.name ?? TransactionText.uncategorised
    }

    /// The category picker's VoiceOver value, with the parent for a subcategory: "Groceries, under Food".
    public var categorySpokenValue: String {
        TransactionCategoryGroup.spokenValue(of: categoryID, in: categories)
    }

    public var payeeName: String {
        TransactionText.trimmed(payeeText) ?? "None"
    }

    public var payeeSuggestions: [TransactionSuggestion] {
        guard payeeID == nil, TransactionText.trimmed(payeeText) != nil else {
            return []
        }
        return TransactionSuggestions.payees(matching: payeeText, payees: payees, transactions: transactions)
    }

    /// Picks a suggested payee and, if no category is set, the category last used with it.
    public func choosePayee(_ suggestion: TransactionSuggestion) {
        payeeText = suggestion.text
        payeeID = suggestion.payeeID
        if categoryID == nil, let suggested = suggestion.categoryID,
            categories.first(where: { $0.id == suggested })?.kind.matches(type) == true
        {
            categoryID = suggested
        }
    }
}

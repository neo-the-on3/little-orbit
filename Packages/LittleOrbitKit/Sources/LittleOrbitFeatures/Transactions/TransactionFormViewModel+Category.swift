import Foundation
import LittleOrbitDomain

// The entry sheet's Category and Payee rows (#23, #24): the category choices and the iOS picker with inline
// create, payee autocomplete, and the payee's last-used category. Everything here reads the ledger the
// sheet loaded when it opened.
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

    /// Whether the Category row opens the searchable picker with inline create (#24), rather than the menu.
    public var hasCategoryPicker: Bool { categoryPicking != nil }

    /// The category picker for this transaction's kind, with the current category checked. Nothing for a
    /// transfer, which has no category. It reads the categories once, when it's made.
    public func makeCategoryPicker() -> CategoryPickerViewModel? {
        guard let categoryPicking, type != .transfer else {
            return nil
        }
        return CategoryPickerViewModel(
            kind: type == .income ? .income : .expense,
            selection: categoryID,
            useCases: categoryPicking,
            changed: categoriesChanged,
        )
    }

    /// Done in the picker: its checked category goes on the form, a category made there included. The amount
    /// and every other field stay as they were (#24 AC 5).
    public func chooseCategory(from picker: CategoryPickerViewModel) {
        if let chosen = picker.selectedCategory {
            if let index = categories.firstIndex(where: { $0.id == chosen.id }) {
                categories[index] = chosen
            } else {
                categories.append(chosen)
            }
        }
        categoryID = picker.selection
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

    /// Picks a suggested payee and preselects the category last used with it (#24 AC 4).
    public func choosePayee(_ suggestion: TransactionSuggestion) {
        payeeText = suggestion.text
        payeeID = suggestion.payeeID
        preselectCategory(suggestion.categoryID)
    }

    /// A typed name that is an existing payee's, ignoring case and outer spaces, is that payee: it's reused on
    /// save, as before, and now preselects its last-used category as picking it does (#24 16:7702).
    func matchTypedPayee() {
        guard isLoaded, payeeID == nil, type != .transfer, let name = TransactionText.trimmed(payeeText),
            let payee = payees.first(where: { $0.isPickable && $0.matches(name) })
        else {
            return
        }
        payeeID = payee.id
        preselectCategory(payee.defaultCategoryID)
    }

    /// Sets the payee's last-used category, unless the user chose a category by hand. A category that's
    /// deleted, archived or of the other kind is never preselected (#24 v2 QA, #11 nullify); then a category
    /// only an earlier payee preselected is cleared, so it doesn't look like this payee's.
    private func preselectCategory(_ id: UUID?) {
        guard categoryID == nil || categoryID == preselectedCategoryID else {
            return
        }
        let usable = id.flatMap { id in
            categories.first { $0.id == id && $0.deletedAt == nil && !$0.isArchived && $0.kind.matches(type) }
        }
        preselectedCategoryID = usable?.id
        categoryID = usable?.id
    }
}

extension Payee {
    /// A payee the form offers: live and not archived.
    fileprivate var isPickable: Bool { deletedAt == nil && !isArchived }

    /// The same name, ignoring case, as the save's payee reuse compares (`resolvePayee`).
    fileprivate func matches(_ trimmedName: String) -> Bool {
        name.compare(trimmedName, options: [.caseInsensitive]) == .orderedSame
    }
}

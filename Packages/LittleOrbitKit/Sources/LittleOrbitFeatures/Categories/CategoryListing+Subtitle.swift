import LittleOrbitDomain

extension CategoryListing {
    /// A category row's subtitle on the Categories screen and in the transaction form's category picker
    /// (D303): “Expense · 25 transactions”, counting what uses the category itself, and for a top-level
    /// category with unarchived subcategories “Expense · 25 transactions · 2 subcategories”, or
    /// “Expense · 2 subcategories” when nothing uses it itself. An archived parent shows only its own use.
    func rowSubtitle(of category: TransactionCategory) -> String {
        let subcategoryCount =
            category.parentID == nil && !category.isArchived
            ? subcategories(of: category.id).filter { !$0.isArchived }.count : 0
        guard subcategoryCount > 0 else {
            return CategoryText.usage(kind: category.kind, count: uses(of: category.id))
        }
        return CategoryText.parentSummary(
            kind: category.kind,
            count: uses(of: category.id),
            subcategoryCount: subcategoryCount,
        )
    }
}

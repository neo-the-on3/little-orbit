import Foundation

// The Move To footer and the budgets a merge or move switches to its target (#25 part 6, D295.1), apart from
// `CategoriesViewModel` to keep each file short.
extension CategoriesViewModel {
    /// "Only expense categories are offered. Food & Dining and Groceries are deleted after the move; budgets
    /// that used them now use Shopping." The budget clause needs a chosen target and at least one of
    /// `budgetNames`, the budgets that pick the category or a subcategory (D295.1).
    public func moveFooter(forDeleting id: UUID, into targetID: UUID? = nil, budgetNames: [String] = []) -> String {
        guard let category = listing.category(id) else {
            return ""
        }
        let names = ([category] + listing.subcategories(of: id)).map(\.name)
        let deleted =
            if let target = targetID.flatMap(listing.category), !budgetNames.isEmpty {
                CategoryText.deletedAfterMove(names, budgetsMoveTo: target.name)
            } else {
                CategoryText.deletedAfterMove(names)
            }
        return CategoryText.sentences([CategoryText.onlyKindOffered(category.kind), deleted])
    }

    /// The budgets that pick the category or one of its subcategories, which Move switches to the target
    /// (D295.1). It reads the store, so only `makeTargetChoice` calls it, once, never a view body.
    public func budgetNames(forDeleting id: UUID) -> [String] {
        (try? useCases.categories.deleteCategory.deletionImpact(of: id).budgetNames) ?? []
    }

    /// The budgets that pick the category itself, which a merge switches to the survivor (D295.1). It reads
    /// the store, so only `makeTargetChoice` calls it, once, never a view body.
    public func budgetNames(merging id: UUID) -> [String] {
        (try? useCases.categories.mergeCategories.mergeImpact(of: id).budgetNames) ?? []
    }
}

import Foundation

/// Seeds the built-in categories once, on a store's first launch (D291.7).
@MainActor
public protocol SeedDefaultCategoriesUseCase {
    /// Adds the default categories only to a brand-new, empty store; otherwise does nothing. Returns whether it
    /// added them.
    @discardableResult
    func seedIfFirstLaunch() throws -> Bool
}

@MainActor
public struct DefaultSeedDefaultCategoriesUseCase: SeedDefaultCategoriesUseCase {
    private let repository: any LedgerRepository
    private let names: any DefaultCategoryNaming

    public init(repository: any LedgerRepository, names: any DefaultCategoryNaming) {
        self.repository = repository
        self.names = names
    }

    /// Seeds only when both hold, with no marker and no schema change:
    /// - the store is new (`LedgerRepository.isNewStore`): created on this launch and not written to yet;
    /// - it holds no categories (archived ones included), no accounts and no transactions.
    ///
    /// So deleting every category never brings the defaults back, even if nothing else is left: on a later
    /// launch the store file already exists, and on this launch the deletes were writes. A restore or an import
    /// writes too, so neither seeds, whatever it brought in. The composition root calls this once at launch,
    /// before anything else writes; `ledgerForEntry` calls it again, which is a no-op by then.
    @discardableResult
    public func seedIfFirstLaunch() throws -> Bool {
        guard repository.isNewStore,
            try repository.categories().isEmpty,
            try repository.accounts().isEmpty,
            try repository.transactions().isEmpty
        else {
            return false
        }
        try repository.seedDefaultCategories(names: names)
        return true
    }
}

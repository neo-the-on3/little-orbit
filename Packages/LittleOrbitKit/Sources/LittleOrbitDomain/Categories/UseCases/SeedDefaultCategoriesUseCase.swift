import Foundation

/// Seeds the built-in categories once per store, on the first launch of an empty store (D291.7, D293).
@MainActor
public protocol SeedDefaultCategoriesUseCase {
    /// Adds the default categories while the store's seeding is still pending and the store is empty;
    /// otherwise does nothing. Returns whether it added them. A failed save throws and leaves the seeding
    /// pending, so the next launch tries again.
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

    /// Seeds only when both hold (D293.1):
    /// - the seeding is still pending (`LedgerRepository.isDefaultSeedPending`): the store was created brand
    ///   new and no seed, restore or import has completed since;
    /// - the store holds no categories (archived ones included), no accounts and no transactions.
    ///
    /// The seeding is marked done after the seed save succeeds, or when a retry finds the store no longer empty. Deleting every category never makes it
    /// pending again, and a completed restore or import marks it done, so none of them leads to a seed. Only the
    /// composition root calls this, once at launch; nothing else seeds, the transaction form included.
    @discardableResult
    public func seedIfFirstLaunch() throws -> Bool {
        guard repository.isDefaultSeedPending else {
            return false
        }
        guard try repository.categories().isEmpty,
            try repository.accounts().isEmpty,
            try repository.transactions().isEmpty
        else {
            // The user added something before a retry: nothing is seeded, now or after they delete it all.
            repository.markDefaultSeedDone()
            return false
        }
        try repository.seedDefaultCategories(names: names)
        repository.markDefaultSeedDone()
        return true
    }
}

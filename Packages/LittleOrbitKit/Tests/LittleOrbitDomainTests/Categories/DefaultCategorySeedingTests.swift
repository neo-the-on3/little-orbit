import Foundation
import LittleOrbitDomain
import Testing

/// D291.7, D293: the default categories are seeded once, at the first launch of an empty store, retried while
/// the seeding is pending and the store is still empty, and never again.
@MainActor
@Suite("Default category seeding (D291.7, D293)")
struct DefaultCategorySeedingTests {
    private func seeding(_ repository: any LedgerRepository) -> any SeedDefaultCategoriesUseCase {
        DefaultSeedDefaultCategoriesUseCase(repository: repository, names: TestCategoryNames())
    }

    @Test("A fresh store is seeded at launch, before any form opens, with all 18 under their fixed ids")
    func launchSeedsAFreshStore() throws {
        let repository = try FakeLedgerRepository()
        #expect(repository.isDefaultSeedPending)
        let useCases = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames())
        #expect(try useCases.seedDefaults?.seedIfFirstLaunch() == true)
        let categories = try useCases.loadLedger.ledger().categories
        #expect(categories.count == 18)
        #expect(Set(categories.map(\.id)) == Set(DefaultCategory.allCases.map(\.id)))
        #expect(!repository.isDefaultSeedPending)
    }

    @Test("A store with an account but no categories isn't seeded, at launch or when a form opens")
    func storeWithAnAccountIsNotSeeded() throws {
        let repository = try FakeLedgerRepository(accounts: [Account(name: "Wallet", currencyCode: "INR")])
        let useCases = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames())
        #expect(try useCases.seedDefaults?.seedIfFirstLaunch() == false)
        #expect(try useCases.loadLedger.ledgerForEntry().categories.isEmpty)
    }

    @Test("Deleting every category, even with nothing else left, never brings the defaults back")
    func deletingEverythingDoesNotReseed() throws {
        let repository = try FakeLedgerRepository()
        let seeding = seeding(repository)
        try seeding.seedIfFirstLaunch()
        for category in try repository.categories() where category.parentID == nil {
            try repository.deleteCategory(id: category.id, reassigningTo: nil)
        }
        #expect(try repository.categories().isEmpty)
        #expect(try seeding.seedIfFirstLaunch() == false)
        #expect(try repository.categories().isEmpty)
    }

    @Test("A store that already has categories is left as it is, its stored symbols included")
    func existingCategoriesAreKept() throws {
        var food = TransactionCategory(id: DefaultCategoryID.food, name: "Food", kind: .expense)
        food.iconName = "basket"
        let repository = try FakeLedgerRepository(categories: [food])
        #expect(try seeding(repository).seedIfFirstLaunch() == false)
        #expect(try repository.categories().map(\.iconName) == ["basket"])
    }

    @Test("D293: a store with no pending marker, an existing install, counts as seeded and is never seeded")
    func noMarkerMeansSeeded() throws {
        let repository = try FakeLedgerRepository(seedPending: false)
        #expect(try seeding(repository).seedIfFirstLaunch() == false)
        #expect(try repository.categories().isEmpty)
    }

    @Test("A store with an account but no categories isn't seeded, and the seeding is marked done")
    func storeInUseMarksTheSeedingDone() throws {
        let repository = try FakeLedgerRepository(accounts: [Account(name: "Wallet", currencyCode: "INR")])
        #expect(repository.isDefaultSeedPending)
        #expect(try seeding(repository).seedIfFirstLaunch() == false)
        #expect(!repository.isDefaultSeedPending)
    }
}

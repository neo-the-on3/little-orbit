import Foundation
import LittleOrbitDomain
import XCTest

/// D291.7 against each store: the defaults are seeded once, at the first launch of an empty store, and a
/// delete, a restore or an import never brings them back. `make` opens a brand-new store.
@MainActor
func assertDefaultsAreSeededOnce(make: MakeRepository) throws {
    try assertLaunchSeedsAFreshStore(make: make)
    try assertDeletingEveryCategoryDoesNotReseed(make: make)
    try assertRestoreWithoutCategoriesDoesNotReseed(make: make)
    try assertImportWithoutCategoriesDoesNotReseed(make: make)
}

@MainActor
private func seeding(_ repository: any LedgerRepository) -> any SeedDefaultCategoriesUseCase {
    DefaultSeedDefaultCategoriesUseCase(repository: repository, names: TestCategoryNames())
}

@MainActor
private func assertLaunchSeedsAFreshStore(make: MakeRepository) throws {
    let repository = try make()
    XCTAssertTrue(repository.isNewStore)
    XCTAssertTrue(try seeding(repository).seedIfFirstLaunch())
    XCTAssertEqual(try repository.categories().count, 18)
    XCTAssertFalse(repository.isNewStore)
    XCTAssertFalse(try seeding(repository).seedIfFirstLaunch())
    XCTAssertEqual(try repository.categories().count, 18)
}

@MainActor
private func assertDeletingEveryCategoryDoesNotReseed(make: MakeRepository) throws {
    let repository = try make()
    try seeding(repository).seedIfFirstLaunch()
    for category in try repository.categories() where category.parentID == nil {
        try repository.deleteCategory(id: category.id, reassigningTo: nil)
    }
    XCTAssertTrue(try repository.categories().isEmpty)
    XCTAssertFalse(try seeding(repository).seedIfFirstLaunch())
    XCTAssertTrue(try repository.categories().isEmpty)
}

/// A restore of a backup with no categories, after the launch seeding and into a store never seeded, adds none.
@MainActor
private func assertRestoreWithoutCategoriesDoesNotReseed(make: MakeRepository) throws {
    let backup = LedgerSnapshot(accounts: [Account(name: "Cash", currencyCode: "USD")])
    let seeded = try make()
    try seeding(seeded).seedIfFirstLaunch()
    try XCTUnwrap(seeded as? any LedgerBackupSource).replaceLedger(with: backup)
    XCTAssertFalse(try seeding(seeded).seedIfFirstLaunch())
    XCTAssertTrue(try seeded.categories().isEmpty)

    let fresh = try make()
    try XCTUnwrap(fresh as? any LedgerBackupSource).replaceLedger(with: LedgerSnapshot())
    XCTAssertFalse(fresh.isNewStore)
    XCTAssertFalse(try seeding(fresh).seedIfFirstLaunch())
    XCTAssertTrue(try fresh.categories().isEmpty)
}

/// An import writes its records through the repository, so a store it filled first is never seeded.
@MainActor
private func assertImportWithoutCategoriesDoesNotReseed(make: MakeRepository) throws {
    let repository = try make()
    let account = try saveCash(in: repository, opening: "10.00")
    try repository.saveTransaction(Transaction(type: .expense, amount: decimal("2.00"), accountID: account.id))
    XCTAssertFalse(try seeding(repository).seedIfFirstLaunch())
    XCTAssertTrue(try repository.categories().isEmpty)
}

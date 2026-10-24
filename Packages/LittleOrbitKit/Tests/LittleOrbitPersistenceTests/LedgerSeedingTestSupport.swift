import Foundation
import LittleOrbitDomain
import XCTest

/// D291.7 and D293 against each store. `make` opens a brand-new store, whose seeding is pending. Calling the
/// seeding again on the same store stands in for the next launch; the SwiftData tests also relaunch on a file.
@MainActor
func assertDefaultsAreSeededOnce(make: MakeRepository) throws {
    try assertLaunchSeedsAFreshStore(make: make)
    try assertFailedSeedIsRetriedOnTheNextLaunch(make: make)
    try assertRestoreAfterAFailedSeedCountsAsSeeded(make: make)
    try assertRestoreOfAnEmptyBackupIntoAFreshStoreCountsAsSeeded(make: make)
    try assertDeletingEveryCategoryDoesNotReseed(make: make)
    try assertARetryOnAStoreInUseSeedsNothing(make: make)
}

@MainActor
func seeding(_ repository: any LedgerRepository) -> any SeedDefaultCategoriesUseCase {
    DefaultSeedDefaultCategoriesUseCase(repository: repository, names: TestCategoryNames())
}

@MainActor
private func assertLaunchSeedsAFreshStore(make: MakeRepository) throws {
    let repository = try make()
    XCTAssertTrue(repository.isDefaultSeedPending)
    XCTAssertTrue(try seeding(repository).seedIfFirstLaunch())
    XCTAssertEqual(try repository.categories().count, 18)
    XCTAssertFalse(repository.isDefaultSeedPending)
    XCTAssertFalse(try seeding(repository).seedIfFirstLaunch())
    XCTAssertEqual(try repository.categories().count, 18)
}

/// D293.5: the first seed save fails, the next launch seeds the 18 defaults and the store counts as seeded.
@MainActor
private func assertFailedSeedIsRetriedOnTheNextLaunch(make: MakeRepository) throws {
    let repository = SeedFailingRepository(try make())
    XCTAssertThrowsError(try seeding(repository).seedIfFirstLaunch())
    XCTAssertTrue(repository.isDefaultSeedPending)
    XCTAssertTrue(try repository.categories().isEmpty)
    repository.failsSeed = false
    XCTAssertTrue(try seeding(repository).seedIfFirstLaunch())
    XCTAssertEqual(try repository.categories().count, 18)
    XCTAssertFalse(repository.isDefaultSeedPending)
}

/// D293.2, D293.5: after a restore the store counts as seeded (the pending marker is gone), and a following
/// launch seeds nothing, even after a failed first seed.
@MainActor
private func assertRestoreAfterAFailedSeedCountsAsSeeded(make: MakeRepository) throws {
    let base = try make()
    let repository = SeedFailingRepository(base)
    XCTAssertThrowsError(try seeding(repository).seedIfFirstLaunch())
    try XCTUnwrap(base as? any LedgerBackupSource)
        .replaceLedger(with: LedgerSnapshot(accounts: [Account(name: "Cash", currencyCode: "USD")]))
    XCTAssertFalse(repository.isDefaultSeedPending)
    repository.failsSeed = false
    XCTAssertFalse(try seeding(repository).seedIfFirstLaunch())
    XCTAssertTrue(try repository.categories().isEmpty)
}

/// D293.2, D293.5: a restore from an empty backup into a fresh store leaves it counting as seeded (the pending
/// marker is gone), and a following launch seeds nothing.
@MainActor
private func assertRestoreOfAnEmptyBackupIntoAFreshStoreCountsAsSeeded(make: MakeRepository) throws {
    let repository = try make()
    XCTAssertTrue(repository.isDefaultSeedPending)
    try XCTUnwrap(repository as? any LedgerBackupSource).replaceLedger(with: LedgerSnapshot())
    XCTAssertFalse(repository.isDefaultSeedPending)
    XCTAssertFalse(try seeding(repository).seedIfFirstLaunch())
    XCTAssertTrue(try repository.categories().isEmpty)
}

@MainActor
private func assertDeletingEveryCategoryDoesNotReseed(make: MakeRepository) throws {
    let repository = try make()
    try seeding(repository).seedIfFirstLaunch()
    for category in try repository.categories() where category.parentID == nil {
        try repository.deleteCategory(id: category.id, reassigningTo: nil)
    }
    XCTAssertTrue(try repository.categories().isEmpty)
    XCTAssertFalse(repository.isDefaultSeedPending)
    XCTAssertFalse(try seeding(repository).seedIfFirstLaunch())
    XCTAssertTrue(try repository.categories().isEmpty)
}

/// A retry that finds the user already added something seeds nothing and marks the seeding done, so deleting it
/// all later still seeds nothing. An import writes the same way, so neither does an import.
@MainActor
private func assertARetryOnAStoreInUseSeedsNothing(make: MakeRepository) throws {
    let repository = SeedFailingRepository(try make())
    XCTAssertThrowsError(try seeding(repository).seedIfFirstLaunch())
    repository.failsSeed = false
    let account = try saveCash(in: repository, opening: "10.00")
    try repository.saveTransaction(Transaction(type: .expense, amount: decimal("2.00"), accountID: account.id))
    XCTAssertFalse(try seeding(repository).seedIfFirstLaunch())
    XCTAssertFalse(repository.isDefaultSeedPending)
    XCTAssertTrue(try repository.categories().isEmpty)
}

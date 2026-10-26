import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Every window shows live data (D187.4). The iOS Categories and Payees screens reload when the shared store
/// moves on, so a merge, delete or archive in another window, or a restore, never leaves an open list showing
/// a removed category or payee, and the D302 Unarchive prompt is decided from the store as it is now (#155,
/// #156 and #159 NB1, NB5). Names are made up.
@MainActor
@Suite("Categories and Payees screens follow the store")
struct CategoriesLiveUpdateTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private func categoriesFeature(_ repository: InMemoryLedgerRepository, _ updates: LedgerUpdates?)
        -> CategoriesFeature
    {
        let editing = DefaultCategoryEditingUseCase(repository: repository)
        return CategoriesFeature(
            useCases: CategoryScreenUseCases(
                load: editing,
                edit: editing,
                categories: CategoryUseCases(repository: repository),
            ),
            updates: updates,
        )
    }

    private func payeesFeature(_ repository: InMemoryLedgerRepository, _ updates: LedgerUpdates) -> PayeesFeature {
        PayeesFeature(
            useCases: PayeeScreenUseCases(
                load: DefaultLoadPayeesUseCase(repository: repository),
                manage: CategoryUseCases(repository: repository).managePayees,
            ),
            updates: updates,
        )
    }

    @Test("A merge on one Categories screen moves the revision every open screen reloads on")
    func categoriesMerge() throws {
        let repository = try F.repository()
        let updates = LedgerUpdates()
        let feature = categoriesFeature(repository, updates)
        let open = feature.makeScreen()
        open.load()
        let other = feature.makeScreen()
        other.load()
        let revision = feature.revision

        #expect(other.merge(DefaultCategoryID.groceries, into: DefaultCategoryID.shopping))
        #expect(feature.revision > revision)
        // What the screen does on the new revision.
        open.load()
        #expect(open.category(DefaultCategoryID.groceries) == nil)
    }

    @Test("After another window archives a parent, Unarchive on its subcategory asks first (D302)")
    func unarchivePromptFollowsTheStore() throws {
        let repository = try F.repository()
        let updates = LedgerUpdates()
        let feature = categoriesFeature(repository, updates)
        let open = feature.makeScreen()
        open.load()
        try CategoryUseCases(repository: repository).archiveCategory.archive(DefaultCategoryID.groceries)
        open.load()
        let other = feature.makeScreen()
        other.load()
        let revision = feature.revision

        #expect(other.archive(DefaultCategoryID.food))
        #expect(feature.revision > revision)
        open.load()
        open.requestUnarchive(DefaultCategoryID.groceries)
        #expect(open.unarchivePrompt?.id == DefaultCategoryID.groceries)
    }

    @Test("A payee merge on one Payees screen moves the revision; a reload drops the merged payee")
    func payeesMerge() throws {
        let repository = try F.repository()
        let parcel = Payee(name: "Parcel Point")
        let parcelIn = Payee(name: "PARCELPOINT.IN")
        try repository.savePayee(parcel)
        try repository.savePayee(parcelIn)
        let updates = LedgerUpdates()
        let feature = payeesFeature(repository, updates)
        let open = feature.makeScreen()
        open.load()
        let other = feature.makeScreen()
        other.load()
        other.selection = [parcel.id, parcelIn.id]
        other.startMerge()
        other.survivorID = parcel.id
        let revision = feature.revision

        #expect(other.merge())
        #expect(feature.revision > revision)
        #expect(open.rows.map(\.name) == ["Parcel Point", "PARCELPOINT.IN"], "Stale until it reloads")
        open.load()
        #expect(open.rows.map(\.name) == ["Parcel Point"])
    }

    @Test("A restore moves the revision too; a screen with no shared updates stays at 0")
    func restoreAndNoUpdates() throws {
        let repository = try F.repository()
        let updates = LedgerUpdates()
        let feature = payeesFeature(repository, updates)
        let revision = feature.revision
        updates.ledgerReplaced()
        #expect(feature.revision == revision + 1)
        #expect(categoriesFeature(repository, nil).revision == 0)
    }
}

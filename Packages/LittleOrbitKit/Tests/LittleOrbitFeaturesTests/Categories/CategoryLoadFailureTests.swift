import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The Categories screen’s load and save failure alerts (D299).
@MainActor
@Suite("Categories screen load failure")
struct CategoryLoadFailureTests {
    typealias Setup = CategoriesViewModelTests.Setup

    @Test("A list that can’t be read shows “Couldn’t Load Categories” / “Try again.”, not the save failure (D299)")
    func loadFails() throws {
        let repository = try TransactionFeatureFixture.repository()
        let editing = DefaultCategoryEditingUseCase(repository: repository)
        let model = CategoriesViewModel(
            useCases: CategoryScreenUseCases(
                load: FailingCategoryLoad(),
                edit: editing,
                categories: CategoryUseCases(repository: repository),
            )
        )
        model.load()
        #expect(model.alert?.title == "Couldn’t Load Categories")
        #expect(model.alert?.message == "Try again.")
        #expect(model.groups.isEmpty)
    }

    @Test("A failed save still shows “Couldn’t Save Changes” (D295.5, D299)")
    func saveFailsStillSaysSave() throws {
        let setup = try Setup()
        setup.model.unarchive(UUID())
        #expect(setup.model.alert?.title == "Couldn’t Save Changes")
    }
}

/// A category list that can't be read.
@MainActor
struct FailingCategoryLoad: LoadCategoriesUseCase {
    struct Failure: Error {}

    func listing() throws -> CategoryListing {
        throw Failure()
    }
}

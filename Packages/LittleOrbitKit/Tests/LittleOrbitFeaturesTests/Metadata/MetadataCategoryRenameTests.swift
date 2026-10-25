import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// Ending a rename in the Mac Metadata manager's Categories table by clicking away or renaming another row
/// (Tech Architect's NB4 on #169). Names are made up.
extension MetadataCategoriesViewModelTests {
    @Test("Clicking away saves a valid name, as Return does")
    func clickAwaySaves() throws {
        let setup = try Setup()
        setup.model.beginRename(DefaultCategoryID.transport)
        setup.model.renameText = "Getting Around"
        #expect(setup.model.endRename(of: DefaultCategoryID.transport))
        #expect(setup.model.renaming == nil)
        #expect(try setup.category(DefaultCategoryID.transport)?.name == "Getting Around")
    }

    @Test("Clicking away from a name with an error keeps the old name and leaves no field or error behind (NB4)")
    func clickAwayWithError() throws {
        let setup = try Setup()
        setup.model.beginRename(DefaultCategoryID.transport)
        setup.model.renameText = "Housing"
        // Return first: the error shows and the row keeps editing.
        #expect(!setup.model.commitRename())
        #expect(setup.model.statusText == "There’s already a category named “Housing” here.")
        // Then the user clicks another row.
        #expect(!setup.model.endRename(of: DefaultCategoryID.transport))
        #expect(setup.model.renaming == nil)
        #expect(setup.model.statusText == "1 selected")
        #expect(try setup.category(DefaultCategoryID.transport)?.name == "Transport")
    }

    @Test("Focus leaving an earlier row's field doesn't end the rename now on another row")
    func clickAwayFromOtherRow() throws {
        let setup = try Setup()
        setup.model.beginRename(DefaultCategoryID.transport)
        setup.model.renameText = "Housing"
        #expect(!setup.model.endRename(of: DefaultCategoryID.food))
        #expect(setup.model.renaming?.categoryID == DefaultCategoryID.transport)
        #expect(setup.model.renameText == "Housing")
    }

    @Test("Renaming another row first ends the current rename: a valid name is saved, one with an error dropped")
    func renameAnotherRow() throws {
        let setup = try Setup()
        setup.model.beginRename(DefaultCategoryID.transport)
        setup.model.renameText = "Getting Around"
        setup.model.beginRename(DefaultCategoryID.food)
        #expect(try setup.category(DefaultCategoryID.transport)?.name == "Getting Around")
        #expect(setup.model.renaming?.categoryID == DefaultCategoryID.food)
        #expect(setup.model.renameText == "Food & Dining")

        setup.model.renameText = "Housing"
        setup.model.beginRename(DefaultCategoryID.transport)
        #expect(try setup.category(DefaultCategoryID.food)?.name == "Food & Dining")
        #expect(setup.model.renaming?.categoryID == DefaultCategoryID.transport)
        #expect(
            setup.model.statusText
                == "Return saves · Esc cancels · names must be unique among categories of the same kind"
        )
    }
}

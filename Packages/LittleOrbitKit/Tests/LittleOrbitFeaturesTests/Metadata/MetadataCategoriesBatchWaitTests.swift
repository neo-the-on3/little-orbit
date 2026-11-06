import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// D399: while a Bulk Edit, or its Undo or Redo, runs in any window, Metadata's Merge, Delete/Move,
/// Unarchive, rename commit and editor Save wait, with nothing written.
extension MetadataCategoriesViewModelTests {
    @Test("Merge, Delete, Move, Unarchive, rename and Save write nothing while a batch runs")
    func writesWaitForBatch() throws {
        let setup = try Setup()
        let food = DefaultCategoryID.food
        let transport = DefaultCategoryID.transport
        let interest = DefaultCategoryID.interest
        #expect(setup.updates.beginBatch())
        #expect(setup.model.isWaitingForBatch)
        #expect(!setup.model.writesEnabled)

        setup.model.selection = [food, transport]
        setup.model.startMerge()
        #expect(setup.model.merge == nil, "Merge does not open while a batch runs")

        setup.model.selection = [transport]
        setup.model.requestDelete()
        #expect(setup.model.screen.deletePrompt == nil, "Delete does not open while a batch runs")

        setup.model.startMove(transport)
        #expect(setup.model.moveChoice == nil)

        setup.model.beginRename(transport)
        setup.model.renameText = "Travel"
        #expect(!setup.model.commitRename())
        #expect(setup.model.renaming != nil, "The field stays open; the name is not saved")
        #expect(try setup.category(transport)?.name == "Transport")
        setup.model.cancelRename()

        setup.model.openNewCategory(.expense)
        let editor = try #require(setup.model.screen.editor)
        editor.name = "Gadgets"
        #expect(!setup.model.saveOpenEditor())
        #expect(try setup.repository.categories().contains { $0.name == "Gadgets" } == false)

        // Unarchive: archive first outside a batch, then try while busy.
        setup.updates.endBatch()
        #expect(setup.model.screen.archive(interest))
        setup.model.load()
        #expect(setup.updates.beginBatch())
        setup.model.requestUnarchive(interest)
        #expect(try setup.category(interest)?.isArchived == true)
        #expect(setup.model.screen.unarchivePrompt == nil)

        setup.updates.endBatch()
        #expect(!setup.model.isWaitingForBatch)
        setup.model.requestUnarchive(interest)
        #expect(try setup.category(interest)?.isArchived == false)
    }

    @Test("An open Merge sheet’s confirm writes nothing while a batch runs, then works")
    func mergeConfirmWaits() throws {
        let setup = try Setup()
        let food = DefaultCategoryID.food
        let transport = DefaultCategoryID.transport
        // Select food first, then transport, so a tie keeps food (D304.5).
        setup.model.selection = [food]
        setup.model.selection = [food, transport]
        setup.model.startMerge()
        #expect(setup.model.merge != nil)
        #expect(setup.updates.beginBatch())
        #expect(!setup.model.confirmMerge())
        #expect(try setup.category(food) != nil)
        #expect(try setup.category(transport) != nil)
        setup.updates.endBatch()
        #expect(setup.model.confirmMerge())
        #expect(try setup.category(food) != nil)
        #expect(try setup.category(transport) == nil)
    }

    @Test("An open Move sheet’s confirm writes nothing while a batch runs, then works")
    func moveConfirmWaits() throws {
        let setup = try Setup([F.income(300, on: F.date(2026, 10, 3), category: DefaultCategoryID.salary)])
        let salary = DefaultCategoryID.salary
        let interest = DefaultCategoryID.interest
        setup.model.selection = [salary]
        setup.model.requestDelete()
        setup.model.startMove(salary)
        let choice = try #require(setup.model.moveChoice)
        choice.targetID = interest
        #expect(setup.updates.beginBatch())
        #expect(!setup.model.confirmMove())
        #expect(try setup.category(salary) != nil)
        setup.updates.endBatch()
        #expect(setup.model.confirmMove())
        #expect(try setup.category(salary) == nil)
        #expect(try setup.repository.transactions().first?.categoryID == interest)
    }
}

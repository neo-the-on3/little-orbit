import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// The Archived section's subcategory rows (UI Designer, #24 part 4) and the D302 confirmation before
/// unarchiving a subcategory whose parent is archived too. Names are made up.
@MainActor
@Suite("Archived subcategories")
struct ArchivedSubcategoryTests {
    typealias Setup = CategoriesViewModelTests.Setup

    private let food = DefaultCategoryID.food
    private let groceries = DefaultCategoryID.groceries
    private let shopping = DefaultCategoryID.shopping

    @Test("An archived parent is followed by its archived subcategories, indented, with the parent’s name")
    func rowsUnderArchivedParent() throws {
        let setup = try Setup()
        let restaurants = try setup.add("Restaurants", under: food)
        setup.model.load()
        #expect(setup.model.archive(food))
        let rows = setup.model.archivedRows
        #expect(rows.map(\.id) == [food, groceries, restaurants])
        #expect(rows[0].isIndented == false)
        #expect(rows[1].isIndented && rows[2].isIndented)
        #expect(rows[1].subtitle == "Food & Dining")
        #expect(rows[2].subtitle == "Food & Dining")
        #expect(rows[0].subtitle == "Expense · 0 transactions")
    }

    @Test("An archived subcategory of a live parent has its own row, not indented, with the parent’s name")
    func rowUnderLiveParent() throws {
        let setup = try Setup()
        #expect(setup.model.archive(groceries))
        let rows = setup.model.archivedRows
        #expect(rows.map(\.id) == [groceries])
        #expect(rows.first?.isIndented == false)
        #expect(rows.first?.subtitle == "Food & Dining")
    }

    @Test("Unarchiving under a live parent needs no confirmation")
    func noPromptUnderLiveParent() throws {
        let setup = try Setup()
        #expect(setup.model.archive(groceries))
        setup.model.requestUnarchive(groceries)
        #expect(setup.model.unarchivePrompt == nil)
        #expect(try setup.category(groceries)?.isArchived == false)
    }

    @Test("Unarchiving a top-level category needs no confirmation")
    func noPromptForTopLevel() throws {
        let setup = try Setup()
        #expect(setup.model.archive(shopping))
        setup.model.requestUnarchive(shopping)
        #expect(setup.model.unarchivePrompt == nil)
        #expect(try setup.category(shopping)?.isArchived == false)
    }

    @Test("Under an archived parent it asks with D302’s copy, and Cancel changes nothing")
    func promptAndCancel() throws {
        let setup = try Setup()
        #expect(setup.model.archive(food))
        setup.model.requestUnarchive(groceries)
        let prompt = try #require(setup.model.unarchivePrompt)
        #expect(prompt.title == "Unarchive “Groceries”?")
        #expect(
            prompt.message
                == "Its parent, “Food & Dining”, is archived too, so it’s unarchived as well. Other subcategories in “Food & Dining” stay archived."
        )
        #expect(try setup.category(groceries)?.isArchived == true, "Nothing changes until Unarchive")
        setup.model.unarchivePrompt = nil
        #expect(try setup.category(food)?.isArchived == true)
        #expect(try setup.category(groceries)?.isArchived == true)
    }

    @Test("Unarchive brings back the subcategory and its parent; its sibling subcategories stay archived (D291.3)")
    func confirmRestoresOnlyParent() throws {
        let setup = try Setup()
        let restaurants = try setup.add("Restaurants", under: food)
        setup.model.load()
        #expect(setup.model.archive(food))
        setup.model.requestUnarchive(groceries)
        setup.model.confirmUnarchive()
        #expect(setup.model.unarchivePrompt == nil)
        #expect(try setup.category(food)?.isArchived == false)
        #expect(try setup.category(groceries)?.isArchived == false)
        #expect(try setup.category(restaurants)?.isArchived == true, "The sibling stays archived")
        #expect(setup.model.groups.first { $0.id == food }?.subcategories.map(\.id) == [groceries])
        #expect(setup.model.archivedRows.map(\.id) == [restaurants])
        #expect(setup.model.archivedRows.first?.isIndented == false, "Its parent is live now")
    }

    @Test("D302’s strings are catalog entries with curly quotes")
    func catalog() throws {
        let entries = try StringCatalogTests.entries()
        #expect(entries["Unarchive “%1$@”?"] == ["Unarchive “%1$@”?"])
        let message =
            "Its parent, “%1$@”, is archived too, so it’s unarchived as well. Other subcategories in “%1$@” stay archived."
        #expect(entries[message] == [message])
    }
}

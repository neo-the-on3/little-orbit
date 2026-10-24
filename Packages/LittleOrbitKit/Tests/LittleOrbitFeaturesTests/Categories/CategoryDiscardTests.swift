import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// D300 and its amendment for the category sheets: Add Category, Add Subcategory, Edit Category and Edit
/// Subcategory close on Cancel when nothing was entered or changed, and ask “Discard Changes?” otherwise.
@MainActor
@Suite("Category sheets’ Discard Changes? prompt")
struct CategoryDiscardTests {
    typealias Setup = CategoriesViewModelTests.Setup

    private let food = DefaultCategoryID.food
    private let groceries = DefaultCategoryID.groceries
    private let shopping = DefaultCategoryID.shopping

    /// Whether Cancel closes the sheet straight away, and whether it shows the prompt instead.
    private func cancel(_ editor: CategoryEditorViewModel) -> (closes: Bool, asks: Bool) {
        var confirmation = DiscardConfirmation()
        let closes = confirmation.requestDismiss(isDirty: editor.hasUnsavedEdits, from: .cancel)
        return (closes, confirmation.isPresentedFromCancel)
    }

    @Test("Add Category with nothing entered closes; a typed name or a new icon or colour asks first")
    func addCategory() throws {
        let setup = try Setup()
        let editor = setup.model.makeNewCategory()
        #expect(cancel(editor) == (true, false))
        editor.name = "Pet care"
        #expect(cancel(editor) == (false, true))
        editor.name = ""
        #expect(cancel(editor) == (true, false), "Clearing the name again leaves nothing entered")
        editor.symbolName = "pawprint.fill"
        #expect(cancel(editor) == (false, true))
        editor.symbolName = setup.model.makeNewCategory().symbolName
        editor.hue = .teal
        #expect(cancel(editor) == (false, true))
    }

    @Test("Add Subcategory with nothing entered closes; a typed name or another parent asks first")
    func addSubcategory() throws {
        let setup = try Setup()
        let editor = setup.model.makeNewSubcategory()
        #expect(editor.parentID == food)
        #expect(cancel(editor) == (true, false))
        editor.parentID = shopping
        #expect(cancel(editor) == (false, true))
        editor.parentID = food
        editor.name = "Restaurants"
        #expect(cancel(editor) == (false, true))
    }

    @Test("Edit Category closes when unchanged and asks once the name, icon or colour changes")
    func editCategory() throws {
        let setup = try Setup()
        let editor = try #require(setup.model.makeEditor(for: food))
        #expect(cancel(editor) == (true, false))
        editor.name = "Food"
        #expect(cancel(editor) == (false, true))
        editor.name = "Food & Dining"
        #expect(cancel(editor) == (true, false), "Putting the name back leaves nothing changed")
        editor.hue = .red
        #expect(cancel(editor) == (false, true))
    }

    @Test("Edit Subcategory closes when unchanged and asks once the name or parent changes")
    func editSubcategory() throws {
        let setup = try Setup()
        let editor = try #require(setup.model.makeEditor(for: groceries))
        #expect(cancel(editor) == (true, false))
        editor.parentID = shopping
        #expect(cancel(editor) == (false, true))
        editor.parentID = food
        #expect(cancel(editor) == (true, false))
        editor.name = "Supermarket"
        #expect(cancel(editor) == (false, true))
        #expect(try setup.category(groceries)?.name == "Groceries", "Discarding saves nothing")
    }
}

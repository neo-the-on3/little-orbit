import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The category and subcategory editor (#24): name, icon, colour, and a subcategory's Parent row (D287.1).
@MainActor
@Suite("Category editor")
struct CategoryEditorViewModelTests {
    typealias Setup = CategoriesViewModelTests.Setup

    private let food = DefaultCategoryID.food
    private let groceries = DefaultCategoryID.groceries

    @Test("Add Category saves the name, icon and colour as a top-level category of the tab’s kind")
    func addCategory() throws {
        let setup = try Setup()
        setup.model.kind = .income
        let editor = setup.model.makeNewCategory()
        #expect(editor.title == "New Category")
        #expect(editor.kindValue == "Income")
        #expect(!editor.canSave, "An empty name can’t be saved")
        editor.name = "  "
        #expect(!editor.canSave)
        editor.name = "Freelance"
        editor.symbolName = "briefcase.fill"
        editor.hue = .cyan
        #expect(editor.save())
        let saved = try #require(try setup.repository.categories().first { $0.name == "Freelance" })
        #expect(saved.kind == .income)
        #expect(saved.parentID == nil)
        #expect(saved.iconName == "briefcase.fill")
        #expect(saved.colorHex == CategoryHue.cyan.hex)
        #expect(setup.model.groups.contains { $0.parent.name == "Freelance" && $0.parent.hue == .cyan })
    }

    @Test("Add Subcategory takes its parent’s kind, and a taken name shows under the field")
    func addSubcategory() throws {
        let setup = try Setup()
        let editor = setup.model.makeNewSubcategory()
        #expect(editor.title == "New Subcategory")
        #expect(editor.parentID == food)
        #expect(editor.kindValue == "Expense (from parent)")
        #expect(editor.hue == .orange, "It starts with its parent’s colour")
        editor.name = "groceries "
        #expect(!editor.canSave)
        #expect(!editor.save())
        #expect(editor.nameError == "There’s already a category named “Groceries” here.", "It quotes the stored name")
        #expect(editor.alert == nil, "A name error shows under the field, not in an alert (D295.4)")
        editor.name = "Restaurants"
        #expect(editor.save())
        let saved = try #require(try setup.repository.categories().first { $0.name == "Restaurants" })
        #expect(saved.parentID == food)
        #expect(saved.kind == .expense)
    }

    @Test("Edit Subcategory moves it to another same-kind top-level parent (D287.1)")
    func changeParent() throws {
        let setup = try Setup()
        let editor = try #require(setup.model.makeEditor(for: groceries))
        #expect(editor.title == "Edit Subcategory")
        #expect(editor.isSubcategory)
        let parents = editor.parentOptions
        #expect(parents.contains { $0.id == DefaultCategoryID.shopping })
        #expect(!parents.contains { $0.id == DefaultCategoryID.salary }, "Only the same kind")
        #expect(!parents.contains { $0.isSubcategory }, "Only top-level parents")
        editor.parentID = DefaultCategoryID.shopping
        editor.name = "Weekly Shop"
        #expect(editor.save())
        let saved = try #require(try setup.repository.categories().first { $0.id == groceries })
        #expect(saved.parentID == DefaultCategoryID.shopping)
        #expect(saved.name == "Weekly Shop")
        #expect(saved.colorHex == nil, "A subcategory’s stored colour is left alone")
        #expect(setup.removals == 0, "A move isn’t a merge or delete (D287.1)")
    }

    @Test("A name taken under the new parent is refused and nothing changes (D287.1)")
    func changeParentTakenName() throws {
        let setup = try Setup()
        _ = try setup.add("Groceries", under: DefaultCategoryID.shopping)
        setup.model.load()
        let editor = try #require(setup.model.makeEditor(for: groceries))
        editor.parentID = DefaultCategoryID.shopping
        editor.name = "Groceries "
        #expect(!editor.save())
        let saved = try #require(try setup.repository.categories().first { $0.id == groceries })
        #expect(saved.parentID == food)
        #expect(saved.colorHex == nil)
    }

    @Test("A top-level category has no Parent row and shows its own kind")
    func topLevel() throws {
        let setup = try Setup()
        let editor = try #require(setup.model.makeEditor(for: food))
        #expect(editor.title == "Edit Category")
        #expect(!editor.isSubcategory)
        #expect(editor.parentOptions.isEmpty)
        #expect(editor.kindValue == "Expense")
        #expect(editor.symbolName == "fork.knife")
        #expect(editor.hue == .orange)
    }

    // MARK: Name errors (D295.4, D151)

    @Test("A name error shows only once the field is edited, and Save stays off while it’s invalid")
    func nameErrorTiming() throws {
        let setup = try Setup()
        let editor = setup.model.makeNewCategory()
        #expect(editor.nameError == nil, "Nothing shows before the field is edited")
        #expect(!editor.canSave)
        editor.name = "   "
        #expect(editor.nameError == "Enter a name.")
        #expect(!editor.canSave)
        editor.name = String(repeating: "a", count: 101)
        #expect(editor.nameError == "Use 100 characters or fewer.")
        #expect(!editor.canSave)
        editor.name = String(repeating: "👩‍👩‍👧", count: 100)
        #expect(editor.nameError == nil, "100 graphemes fit, however many scalars they take (D39)")
        #expect(editor.canSave)
        editor.name = " Freelance "
        #expect(editor.nameError == nil)
        #expect(editor.save())
    }

    @Test("Save on an untouched empty name shows the error")
    func saveShowsError() throws {
        let setup = try Setup()
        let editor = setup.model.makeNewCategory()
        #expect(!editor.save())
        #expect(editor.nameError == "Enter a name.")
    }

    @Test("A subcategory’s name is taken only under the same parent, ignoring case and outer spaces")
    func duplicateSameParent() throws {
        let setup = try Setup()
        let editor = setup.model.makeNewSubcategory()
        #expect(editor.parentID == food)
        editor.name = "  GROCERIES  "
        #expect(editor.nameError == "There’s already a category named “Groceries” here.")
        #expect(!editor.canSave)
        editor.parentID = DefaultCategoryID.shopping
        #expect(editor.nameError == nil, "Another parent’s Groceries doesn’t clash")
        #expect(editor.canSave)
        editor.name = "food & dining"
        #expect(editor.nameError == nil, "A top-level name doesn’t clash with a subcategory")
    }

    @Test("A top-level category’s name is taken only among categories of the same kind")
    func duplicateSameKind() throws {
        let setup = try Setup()
        let expense = setup.model.makeNewCategory()
        expense.name = " shopping"
        #expect(expense.nameError == "There’s already a category named “Shopping” here.")
        #expect(!expense.canSave)
        expense.name = "Groceries"
        #expect(expense.nameError == nil, "A subcategory’s name doesn’t clash at the top level")
        setup.model.kind = .income
        let income = setup.model.makeNewCategory()
        income.name = "Shopping"
        #expect(income.nameError == nil, "An expense category doesn’t clash with an income one")
        income.name = "salary "
        #expect(income.nameError == "There’s already a category named “Salary” here.")
    }

    @Test("A category keeps its own name without a clash")
    func ownName() throws {
        let setup = try Setup()
        let editor = try #require(setup.model.makeEditor(for: groceries))
        editor.name = "GROCERIES"
        #expect(editor.nameError == nil)
        #expect(editor.canSave)
    }

    // MARK: Failed save (D295.5)

    @Test("A save that fails for another reason says “Couldn’t Save Changes”, and nothing changes")
    func failedSave() throws {
        let setup = try Setup()
        let editing = DefaultCategoryEditingUseCase(repository: setup.repository)
        let model = CategoriesViewModel(
            useCases: CategoryScreenUseCases(
                load: editing,
                edit: FailingEdit(),
                categories: CategoryUseCases(repository: setup.repository),
            )
        ) {}
        model.load()
        let before = try setup.repository.categories()
        let editor = try #require(model.makeEditor(for: groceries))
        editor.name = "Weekly Shop"
        #expect(!editor.save())
        #expect(editor.alert?.title == "Couldn’t Save Changes")
        #expect(editor.alert?.message == "Your categories weren’t changed. Try again.")
        #expect(editor.nameError == nil)
        #expect(try setup.repository.categories() == before)
        let added = model.makeNewCategory()
        added.name = "Freelance"
        #expect(!added.save())
        #expect(added.alert?.title == "Couldn’t Save Changes")
    }

    // MARK: Icons and unsaved edits

    @Test("Every icon has a catalog name, used for the Icon row and VoiceOver")
    func symbolNames() throws {
        let setup = try Setup()
        let editor = try #require(setup.model.makeEditor(for: groceries))
        let options = editor.symbolOptions
        #expect(options.count == 33)
        #expect(options.first { $0.symbol == "cart.fill" }?.name == "Cart")
        #expect(options.first { $0.symbol == "cross.case.fill" }?.name == "First Aid Kit")
        #expect(options.first { $0.symbol == "ellipsis.circle.fill" }?.name == "More")
        #expect(options.allSatisfy { $0.name != $0.symbol && $0.name != "Current Icon" })
        #expect(Set(options.map(\.name)).count == 33, "No two icons share a name")
        #expect(editor.symbolLabel == "Cart")
        editor.symbolName = "wrench.and.screwdriver.fill"
        #expect(editor.symbolLabel == "Tools")
    }

    @Test("A stored icon the editor doesn’t list shows first, as “Current Icon” (D292.2)")
    func unlistedSymbol() throws {
        let setup = try Setup()
        let id = try setup.add("Garden")
        try DefaultCategoryEditingUseCase(repository: setup.repository)
            .save(id, CategoryEdit(name: "Garden", iconName: "leaf.fill", colorHex: nil, parentID: nil))
        setup.model.load()
        let editor = try #require(setup.model.makeEditor(for: id))
        #expect(editor.symbolOptions.count == 34)
        #expect(editor.symbolOptions.first?.symbol == "leaf.fill")
        #expect(editor.symbolOptions.first?.name == "Current Icon")
        #expect(editor.symbolLabel == "Current Icon")
    }

    @Test("Unsaved edits block swiping the sheet away until they’re undone")
    func unsavedEdits() throws {
        let setup = try Setup()
        let editor = try #require(setup.model.makeEditor(for: groceries))
        #expect(!editor.hasUnsavedEdits)
        editor.name = "Weekly Shop"
        #expect(editor.hasUnsavedEdits)
        editor.name = "Groceries"
        #expect(!editor.hasUnsavedEdits)
        editor.parentID = DefaultCategoryID.shopping
        #expect(editor.hasUnsavedEdits)
        let new = setup.model.makeNewCategory()
        #expect(!new.hasUnsavedEdits)
        new.symbolName = "gift.fill"
        #expect(new.hasUnsavedEdits)
    }
}

/// Fails every save with an error that isn't about the name.
@MainActor
private struct FailingEdit: EditCategoryUseCase {
    struct Failure: Error {}

    func add(_: CategoryEdit, kind _: CategoryKind) throws -> UUID {
        throw Failure()
    }

    func save(_: UUID, _: CategoryEdit) throws {
        throw Failure()
    }
}

/// Tester's #155 findings: a row's tap opens its sheet at once, and a new subcategory's colour follows its parent.
@MainActor
@Suite("Category editor sheet")
struct CategoryEditorSheetTests {
    typealias Setup = CategoriesViewModelTests.Setup

    @Test("Tapping a parent row sets its editor sheet straight away, with nothing to wait for")
    func parentOpensAtOnce() throws {
        let setup = try Setup()
        #expect(setup.model.editor == nil)
        setup.model.openEditor(for: DefaultCategoryID.food)
        let editor = try #require(setup.model.editor)
        #expect(editor.categoryID == DefaultCategoryID.food)
        #expect(editor.title == "Edit Category")
        setup.model.openEditor(for: DefaultCategoryID.groceries)
        #expect(setup.model.editor?.categoryID == DefaultCategoryID.groceries)
        setup.model.openNewSubcategory()
        #expect(setup.model.editor?.isNew == true)
    }

    @Test("A subcategory shows its parent’s colour, and picking another parent switches it at once")
    func subcategoryHueFollowsParent() throws {
        let setup = try Setup()
        let new = setup.model.makeNewSubcategory()
        #expect(new.parentID == DefaultCategoryID.food)
        #expect(new.hue == .orange)
        new.parentID = DefaultCategoryID.shopping
        #expect(new.hue == .pink, "Shopping’s colour")
        new.name = "Gadgets"
        #expect(new.save())
        let gadgets = try #require(try setup.repository.categories().first { $0.name == "Gadgets" })
        #expect(gadgets.colorHex == nil, "No colour of its own is written")
        #expect(setup.model.groups.first { $0.id == DefaultCategoryID.shopping }?.subcategories.first?.hue == .pink)
        let editor = try #require(setup.model.makeEditor(for: DefaultCategoryID.groceries))
        #expect(editor.hue == .orange)
        editor.parentID = DefaultCategoryID.transport
        #expect(editor.hue == .blue, "Transport’s colour")
    }

    @Test("A subcategory follows its parent’s new colour, whatever colour it has stored")
    func parentColourChange() throws {
        let setup = try Setup()
        let garden = try setup.add("Garden")
        let seeds = try setup.add("Seeds", under: garden)
        let editing = DefaultCategoryEditingUseCase(repository: setup.repository)
        try editing.save(
            seeds,
            CategoryEdit(name: "Seeds", iconName: nil, colorHex: CategoryHue.red.hex, parentID: garden),
        )
        setup.model.load()
        let parent = try #require(setup.model.makeEditor(for: garden))
        parent.hue = .teal
        #expect(parent.save())
        let group = try #require(setup.model.groups.first { $0.id == garden })
        #expect(group.parent.hue == .teal)
        #expect(group.subcategories.first?.hue == .teal, "Not its stored red")
        let editor = try #require(setup.model.makeEditor(for: seeds))
        #expect(editor.hue == .teal)
        editor.name = "Bulbs"
        #expect(editor.save())
        #expect(try setup.category(seeds)?.colorHex == CategoryHue.red.hex, "The stored value is left alone")
    }
}

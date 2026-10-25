import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Tech Architect's B1 on #155 (no store reads from a view body), and Tester's, UI Designer's and D301's
/// findings at 3d615da: the Parent order, Save until a change, the delete and merge copy, and the subtitle.
/// Names are made up.
@MainActor
@Suite("Categories: #155 review fixes")
struct CategoryReviewFixesTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name
    typealias Setup = CategoriesViewModelTests.Setup

    private let food = DefaultCategoryID.food
    private let groceries = DefaultCategoryID.groceries

    // MARK: B1: reads happen once, never per render

    @Test("Typing a name and re-rendering the editor, the Merge sheet and Move To read the store no more")
    func noReadsPerRender() throws {
        let setup = try Setup()
        let counting = CountingReads(repository: setup.repository)
        let management = DefaultCategoryManagementUseCase(repository: setup.repository)
        let model = CategoriesViewModel(
            useCases: CategoryScreenUseCases(
                load: counting,
                edit: DefaultCategoryEditingUseCase(repository: setup.repository),
                categories: CategoryUseCases(
                    saveCategory: management,
                    moveSubcategory: counting,
                    reorderCategories: management,
                    archiveCategory: management,
                    mergeCategories: counting,
                    deleteCategory: counting,
                    managePayees: DefaultManagePayeesUseCase(repository: setup.repository),
                ),
            )
        )
        model.load()
        #expect(counting.reads == 1)
        // A parent's subtitle counts its own entry in the loaded list, with no read of its own.
        #expect(model.groups.first { $0.id == food }?.parent.subtitle == "Expense · 1 subcategory")
        #expect(counting.reads == 1)
        let editor = try #require(model.makeEditor(for: groceries))
        for text in ["W", "We", "Wee", "Week", "Weekly", "Weekly Shop"] {
            editor.name = text
            render(editor)
            _ = model.groups
            _ = model.archivedRows
        }
        #expect(!editor.parentOptions.isEmpty)
        #expect(counting.reads == 1, "The Parent options come from the loaded tree, once")

        let merge = model.makeTargetChoice(.merge(food))
        #expect(counting.reads == 3, "The Merge rows and its budgets are read once, when the sheet opens")
        for row in merge.rows {
            merge.targetID = row.id
            _ = (merge.rows, merge.header, merge.footer, merge.title)
        }
        let move = model.makeTargetChoice(.move(food))
        for row in move.rows {
            move.targetID = row.id
            _ = (move.rows, move.header, move.footer, move.title)
        }
        #expect(counting.reads == 5, "Choosing rows and re-rendering read nothing more")
    }

    private func render(_ editor: CategoryEditorViewModel) {
        _ = (editor.nameError, editor.canSave, editor.parentOptions, editor.hasUnsavedEdits)
        _ = (editor.symbolOptions, editor.symbolLabel, editor.title, editor.footnote, editor.kindValue)
    }

    // MARK: Parent order (Tester 2, UI Designer)

    @Test("The Parent list follows the tree’s order, after a reorder too, the same on every open")
    func parentOrder() throws {
        let setup = try Setup()
        setup.model.moveCategories(from: IndexSet(integer: 3), to: 0)
        let tree = setup.model.groups.map(\.id)
        let editor = try #require(setup.model.makeEditor(for: groceries))
        #expect(editor.parentOptions.map(\.id) == tree)
        let again = try #require(setup.model.makeEditor(for: groceries))
        #expect(again.parentOptions.map(\.id) == tree)
        #expect(setup.model.makeNewSubcategory().parentOptions.map(\.id) == tree)
    }

    @Test("Categories with the same stored order come out by name, every time")
    func sameOrderTieBreak() throws {
        let setup = try Setup()
        let foodOrder = try #require(try setup.category(food)).sortOrder
        var shopping = try #require(try setup.category(DefaultCategoryID.shopping))
        shopping.sortOrder = foodOrder
        try setup.repository.saveCategory(shopping)
        var aardvark = try #require(try setup.category(try setup.add("Aardvark Club")))
        aardvark.sortOrder = foodOrder
        try setup.repository.saveCategory(aardvark)
        for _ in 0..<3 {
            setup.model.load()
            let names = setup.model.groups.map(\.parent.name)
            let tied = names.filter { ["Aardvark Club", "Food & Dining", "Shopping"].contains($0) }
            #expect(tied == ["Aardvark Club", "Food & Dining", "Shopping"])
            let editor = try #require(setup.model.makeEditor(for: groceries))
            #expect(editor.parentOptions.map(\.name) == names)
        }
    }

    // MARK: Save waits for a change (Tester 3)

    @Test("Save in Edit Category and Edit Subcategory stays off until something changes")
    func saveNeedsAChange() throws {
        let setup = try Setup()
        let subcategory = try #require(setup.model.makeEditor(for: groceries))
        #expect(!subcategory.canSave)
        subcategory.name = "Weekly Shop"
        #expect(subcategory.canSave)
        subcategory.name = "Groceries"
        #expect(!subcategory.canSave, "Back to how it opened")
        subcategory.parentID = DefaultCategoryID.shopping
        #expect(subcategory.canSave)
        let category = try #require(setup.model.makeEditor(for: food))
        #expect(!category.canSave)
        category.hue = .teal
        #expect(category.canSave)
        category.hue = .orange
        category.symbolName = "cart.fill"
        #expect(category.canSave)
    }

    // MARK: Duplicate quotes the stored name (Tester 4)

    @Test("The duplicate-name error quotes the existing category’s stored name, not what was typed")
    func duplicateQuotesStoredName() throws {
        let setup = try Setup()
        let editor = setup.model.makeNewCategory()
        editor.name = "  SHOPPING "
        #expect(editor.nameError == "There’s already a category named “Shopping” here.")
        let sub = setup.model.makeNewSubcategory()
        sub.name = "groceries"
        #expect(sub.nameError == "There’s already a category named “Groceries” here.")
    }

    // MARK: Delete copy (Tester 5 and 6, D301)

    @Test("One transaction: “Moving or leaving it uncategorised”, with one/other plurals (D301)")
    func deleteOneTransaction() throws {
        let setup = try Setup([F.expense(100, on: F.date(2026, 10, 1), category: DefaultCategoryID.housing)])
        setup.model.requestDelete(DefaultCategoryID.housing)
        #expect(
            setup.model.deletePrompt?.message
                == "It’s used by 1 transaction. Archive hides it from pickers and keeps its history. Moving or leaving it uncategorised deletes the category. Deleting can’t be undone."
        )
    }

    @Test("The only transaction in a subcategory: “It’s used by 1 transaction, in Seeds.” (D301)")
    func deleteOneTransactionInSubcategory() throws {
        let setup = try Setup()
        let garden = try setup.add("Garden")
        let seeds = try setup.add("Seeds", under: garden)
        _ = try setup.add("Tools", under: garden)
        try setup.repository.saveTransaction(F.expense(100, on: F.date(2026, 10, 1), category: seeds))
        setup.model.load()
        setup.model.requestDelete(garden)
        #expect(
            setup.model.deletePrompt?.message
                == "It’s used by 1 transaction, in Seeds. Archive hides it from pickers and keeps its history. Moving or leaving it uncategorised deletes the category and its 2 subcategories. Deleting can’t be undone."
        )
    }

    @Test("When no subcategory has transactions the “including those in” clause is left out (D301)")
    func deleteNoSubcategoryUsed() throws {
        let setup = try Setup()
        let garden = try setup.add("Garden")
        _ = try setup.add("Seeds", under: garden)
        try setup.repository.saveTransaction(F.expense(100, on: F.date(2026, 10, 1), category: garden))
        try setup.repository.saveTransaction(F.expense(200, on: F.date(2026, 10, 2), category: garden))
        setup.model.load()
        setup.model.requestDelete(garden)
        #expect(
            setup.model.deletePrompt?.message
                == "It’s used by 2 transactions. Archive hides it from pickers and keeps its history. Moving or leaving them uncategorised deletes the category and its subcategory. Deleting can’t be undone."
        )
    }

    @Test("Only the subcategories with transactions are named, joined by the list formatter (D301)")
    func deleteNamesUsedSubcategories() throws {
        let setup = try Setup()
        let garden = try setup.add("Garden")
        let seeds = try setup.add("Seeds", under: garden)
        _ = try setup.add("Takeaway", under: garden)
        let tools = try setup.add("Tools", under: garden)
        try setup.repository.saveTransaction(F.expense(100, on: F.date(2026, 10, 1), category: seeds))
        try setup.repository.saveTransaction(F.expense(200, on: F.date(2026, 10, 2), category: tools))
        setup.model.load()
        setup.model.requestDelete(garden)
        #expect(
            setup.model.deletePrompt?.message
                == "It’s used by 2 transactions, including those in Seeds and Tools. Archive hides it from pickers and keeps its history. Moving or leaving them uncategorised deletes the category and its 3 subcategories. Deleting can’t be undone."
        )
    }

    // MARK: Merge footnote (D301)

    @Test("Merging a category with subcategories says where they move, before “Merging can’t be undone.”")
    func mergeSubcategoriesMove() throws {
        let setup = try Setup()
        let garden = try setup.add("Garden")
        _ = try setup.add("Seeds", under: garden)
        setup.model.load()
        let one = setup.model.mergeFootnote(for: garden, into: DefaultCategoryID.shopping)
        #expect(one.hasSuffix("Its subcategory moves to “Shopping”. Merging can’t be undone."))
        _ = try setup.add("Tools", under: garden)
        setup.model.load()
        let two = setup.model.mergeFootnote(for: garden, into: DefaultCategoryID.shopping)
        #expect(two.hasSuffix("Its 2 subcategories move to “Shopping”. Merging can’t be undone."))
        let leaf = setup.model.mergeFootnote(for: DefaultCategoryID.housing, into: DefaultCategoryID.shopping)
        #expect(!leaf.contains("subcategor"), "Left out without subcategories")
    }

    // MARK: Parent subtitle (UI Designer)

    @Test("A parent’s subtitle counts only its own transactions, leaves out zero, and uses one/other plurals")
    func parentSubtitle() throws {
        let setup = try Setup()
        let garden = try setup.add("Garden")
        let seeds = try setup.add("Seeds", under: garden)
        setup.model.load()
        func subtitle() -> String? {
            setup.model.groups.first { $0.id == garden }?.parent.subtitle
        }
        #expect(subtitle() == "Expense · 1 subcategory")
        try setup.repository.saveTransaction(F.expense(100, on: F.date(2026, 10, 1), category: seeds))
        _ = try setup.add("Tools", under: garden)
        setup.model.load()
        #expect(subtitle() == "Expense · 2 subcategories", "Seeds’ transaction isn’t the parent’s own")
        try setup.repository.saveTransaction(F.expense(200, on: F.date(2026, 10, 2), category: garden))
        setup.model.load()
        #expect(subtitle() == "Expense · 1 transaction · 2 subcategories")
        try setup.repository.saveTransaction(F.expense(300, on: F.date(2026, 10, 3), category: garden))
        setup.model.load()
        #expect(subtitle() == "Expense · 2 transactions · 2 subcategories")
    }
}

/// Forwards to the real use cases and counts every call that reads the store.
@MainActor
private final class CountingReads: LoadCategoriesUseCase {
    private let editing: DefaultCategoryEditingUseCase
    let management: DefaultCategoryManagementUseCase
    var reads = 0

    init(repository: any LedgerRepository) {
        editing = DefaultCategoryEditingUseCase(repository: repository)
        management = DefaultCategoryManagementUseCase(repository: repository)
    }

    func listing() throws -> CategoryListing {
        reads += 1
        return try editing.listing()
    }
}

extension CountingReads: MoveSubcategoryUseCase, MergeCategoriesUseCase, DeleteCategoryUseCase {
    func parentTargets(for subcategoryID: UUID) throws -> [TransactionCategory] {
        reads += 1
        return try management.parentTargets(for: subcategoryID)
    }

    func move(_ subcategoryID: UUID, toParent parentID: UUID) throws {
        try management.move(subcategoryID, toParent: parentID)
    }

    func mergeTargets(for categoryID: UUID) throws -> [TransactionCategory] {
        reads += 1
        return try management.mergeTargets(for: categoryID)
    }

    func mergeImpact(of categoryID: UUID) throws -> CategoryMergeImpact {
        reads += 1
        return try management.mergeImpact(of: categoryID)
    }

    func merge(_ sourceID: UUID, into survivingID: UUID) throws {
        try management.merge(sourceID, into: survivingID)
    }

    func deletionImpact(of categoryID: UUID) throws -> CategoryDeletionImpact {
        reads += 1
        return try management.deletionImpact(of: categoryID)
    }

    func moveTargets(forDeleting categoryID: UUID) throws -> [TransactionCategory] {
        reads += 1
        return try management.moveTargets(forDeleting: categoryID)
    }

    func delete(_ categoryID: UUID, choice: CategoryDeletion) throws {
        try management.delete(categoryID, choice: choice)
    }
}

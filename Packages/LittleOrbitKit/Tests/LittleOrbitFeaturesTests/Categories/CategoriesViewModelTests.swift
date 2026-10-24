import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// iOS Settings › Categories (#24): the tree, reorder, Archived with Unarchive, delete (D19, D287), merge
/// (D287, D291.1) and clearing the window's Undo after a merge or delete (D287.4). Names are made up.
@MainActor
@Suite("Categories screen")
struct CategoriesViewModelTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @MainActor
    final class Setup {
        let repository: InMemoryLedgerRepository
        let model: CategoriesViewModel
        var removals = 0
        var changes = 0

        init(_ transactions: [Transaction] = []) throws {
            repository = try F.repository(transactions)
            let editing = DefaultCategoryEditingUseCase(repository: repository)
            let useCases = CategoryScreenUseCases(
                load: editing,
                edit: editing,
                categories: CategoryUseCases(repository: repository),
            )
            var changed: () -> Void = {}
            model = CategoriesViewModel(useCases: useCases) { changed() }
            changed = { [unowned self] in changes += 1 }
            model.onRemoval = { [unowned self] in removals += 1 }
            model.load()
        }

        func add(_ name: String, under parentID: UUID? = nil, kind: CategoryKind = .expense) throws -> UUID {
            try CategoryUseCases(repository: repository).saveCategory.add(named: name, kind: kind, parentID: parentID)
                .id
        }

        func category(_ id: UUID) throws -> TransactionCategory? {
            try repository.categories().first { $0.id == id }
        }
    }

    private let food = DefaultCategoryID.food
    private let groceries = DefaultCategoryID.groceries
    private let shopping = DefaultCategoryID.shopping

    @Test("The Expense tab lists top-level categories with their subcategories and what uses each")
    func tree() throws {
        let setup = try Setup([
            F.expense(100, on: F.date(2026, 10, 1), category: DefaultCategoryID.groceries),
            F.expense(200, on: F.date(2026, 10, 2), category: DefaultCategoryID.groceries),
            F.expense(300, on: F.date(2026, 10, 3), category: DefaultCategoryID.transport),
        ])
        let groups = setup.model.groups
        #expect(groups.first?.parent.name == "Food & Dining")
        #expect(
            groups.first?.parent.subtitle == "Expense · 1 subcategory",
            "Only Food & Dining’s own transactions count, and it has none",
        )
        #expect(groups.first?.subcategories.map(\.name) == ["Groceries"])
        #expect(groups.first?.subcategories.first?.subtitle == "Expense · 2 transactions")
        #expect(groups.first { $0.id == DefaultCategoryID.transport }?.parent.subtitle == "Expense · 1 transaction")
        #expect(groups.allSatisfy { $0.parent.name != "Salary" })
        setup.model.kind = .income
        #expect(setup.model.groups.map(\.parent.name) == ["Salary", "Interest", "Gifts Received", "Other Income"])
        #expect(setup.model.groups.first?.parent.subtitle == "Income · 0 transactions")
    }

    @Test("Reorder moves a top-level category, and subcategories only within their parent")
    func reorder() throws {
        let setup = try Setup()
        let restaurants = try setup.add("Restaurants", under: food)
        setup.model.load()
        let before = setup.model.groups.map(\.id)
        setup.model.moveCategories(from: IndexSet(integer: 1), to: 0)
        #expect(setup.model.groups.map(\.id) == [before[1], before[0]] + before.dropFirst(2))
        setup.model.moveSubcategories(of: food, from: IndexSet(integer: 1), to: 0)
        let foodGroup = try #require(setup.model.groups.first { $0.id == food })
        #expect(foodGroup.subcategories.map(\.id) == [restaurants, groceries])
        #expect(setup.removals == 0)
    }

    @Test("Archived categories move to Archived; unarchiving a subcategory brings back only its parent (D291.3)")
    func archiveAndUnarchive() throws {
        let setup = try Setup()
        let restaurants = try setup.add("Restaurants", under: food)
        setup.model.load()
        #expect(setup.model.archive(food))
        #expect(setup.model.groups.allSatisfy { $0.id != food })
        #expect(setup.model.archivedRows.map(\.id) == [food])
        #expect(setup.removals == 0, "Archive is reversed with Unarchive, so Undo stays (D287.2)")
        setup.model.kind = .income
        #expect(setup.model.archivedRows.isEmpty)
        setup.model.kind = .expense
        // Archive the parent's subcategories one by one, then unarchive one of them.
        setup.model.unarchive(food)
        _ = setup.model.archive(groceries)
        _ = setup.model.archive(restaurants)
        _ = setup.model.archive(food)
        setup.model.load()
        #expect(setup.model.archivedRows.map(\.id) == [food])
        try CategoryUseCases(repository: setup.repository).archiveCategory.archive(food)
        setup.model.unarchive(groceries)
        #expect(try setup.category(food)?.isArchived == false)
        #expect(try setup.category(groceries)?.isArchived == false)
    }

    @Test("Delete asks with D19’s choices, and the message ends “Deleting can’t be undone.” (D287.3)")
    func deletePrompt() throws {
        let setup = try Setup([
            F.expense(100, on: F.date(2026, 10, 1), category: DefaultCategoryID.food),
            F.expense(200, on: F.date(2026, 10, 2), category: DefaultCategoryID.groceries),
        ])
        _ = try setup.add("Restaurants", under: food)
        setup.model.load()
        setup.model.requestDelete(food)
        let prompt = try #require(setup.model.deletePrompt)
        #expect(prompt.title == "Delete “Food & Dining”?")
        #expect(!prompt.isUnused)
        #expect(
            prompt.message
                == "It’s used by 2 transactions, including those in Groceries. Archive hides it from pickers and keeps its history. Moving or leaving them uncategorised deletes the category and its 2 subcategories. Deleting can’t be undone.",
            "Restaurants has no transactions, so it isn’t named (D301)",
        )
        setup.model.requestDelete(DefaultCategoryID.housing)
        let unused = try #require(setup.model.deletePrompt)
        #expect(unused.isUnused)
        #expect(unused.message == "Nothing uses it. Deleting can’t be undone.")
    }

    @Test("An unused category’s delete alert names its subcategories as one plural sentence (D295.3)")
    func deletePromptSubcategories() throws {
        let setup = try Setup()
        let garden = try setup.add("Garden")
        _ = try setup.add("Seeds", under: garden)
        setup.model.load()
        setup.model.requestDelete(garden)
        #expect(
            setup.model.deletePrompt?.message
                == "Nothing uses it. Its subcategory is deleted too. Deleting can’t be undone."
        )
        _ = try setup.add("Tools", under: garden)
        setup.model.load()
        setup.model.requestDelete(garden)
        #expect(
            setup.model.deletePrompt?.message
                == "Nothing uses it. Its 2 subcategories are deleted too. Deleting can’t be undone."
        )
    }

    @Test("Moving the transactions deletes the category and clears this window’s Undo (D287.4)")
    func deleteMoving() throws {
        let lunch = F.expense(100, on: F.date(2026, 10, 1), category: DefaultCategoryID.groceries)
        let setup = try Setup([lunch])
        let targets = setup.model.moveTargets(forDeleting: food)
        #expect(!targets.contains { $0.id == food || $0.id == groceries })
        #expect(targets.contains { $0.id == shopping })
        #expect(!targets.contains { $0.id == DefaultCategoryID.salary }, "Only the same kind (D19)")
        #expect(
            setup.model.moveHeader(forDeleting: food)
                == "Move 1 transaction from Food & Dining and its subcategories to:"
        )
        #expect(
            setup.model.moveFooter(forDeleting: food)
                == "Only expense categories are offered. Food & Dining and Groceries are deleted after the move."
        )
        #expect(setup.model.delete(food, movingTo: shopping))
        #expect(try setup.repository.transactions().first?.categoryID == shopping)
        #expect(try setup.category(food) == nil)
        #expect(try setup.category(groceries) == nil)
        #expect(setup.removals == 1)
        #expect(setup.changes == 1)
    }

    @Test("Leaving them uncategorised deletes the category and clears this window’s Undo (D287.4)")
    func deleteLeavingUncategorised() throws {
        let setup = try Setup([F.expense(100, on: F.date(2026, 10, 1), category: DefaultCategoryID.shopping)])
        #expect(setup.model.deleteLeavingUncategorised(shopping))
        #expect(try setup.repository.transactions().first?.categoryID == nil)
        #expect(setup.model.groups.allSatisfy { $0.id != shopping })
        #expect(setup.removals == 1)
    }

    @Test("Merge lists only the same kind, says what happens, and clears this window’s Undo (D287.3, D287.4)")
    func merge() throws {
        let setup = try Setup([F.expense(100, on: F.date(2026, 10, 1), category: DefaultCategoryID.groceries)])
        let targets = setup.model.mergeTargets(for: groceries)
        #expect(targets.contains { $0.id == food })
        #expect(!targets.contains { $0.id == DefaultCategoryID.salary })
        #expect(setup.model.mergeHeader(for: groceries) == "Merge “Groceries” (1 transaction) into:")
        #expect(
            setup.model.mergeFootnote(for: groceries, into: food)
                == "1 transaction will use Food & Dining. Groceries is then deleted. Income categories can’t be merged with expense ones, so they aren’t listed. Merging can’t be undone."
        )
        #expect(
            setup.model.mergeFootnote(for: groceries, into: nil)
                == "Income categories can’t be merged with expense ones, so they aren’t listed. Merging can’t be undone."
        )
        #expect(setup.model.merge(groceries, into: food))
        #expect(try setup.repository.transactions().first?.categoryID == food)
        #expect(try setup.category(groceries) == nil)
        #expect(setup.removals == 1)
    }

    @Test("A merge that would put two same-named subcategories under one parent is refused (D291.1)")
    func mergeClash() throws {
        let setup = try Setup()
        let leisure = try setup.add("Leisure")
        _ = try setup.add("Movies", under: leisure)
        _ = try setup.add("Games", under: leisure)
        let entertainment = DefaultCategoryID.entertainment
        _ = try setup.add("Movies", under: entertainment)
        setup.model.load()
        #expect(!setup.model.merge(leisure, into: entertainment))
        #expect(setup.model.alert?.title == "Can’t Merge Categories")
        #expect(
            setup.model.alert?.message
                == "“Leisure” and “Entertainment” both have a subcategory named “Movies”. Rename or merge one of them first."
        )
        #expect(try setup.category(leisure) != nil, "Nothing changes")
        #expect(setup.removals == 0)

        setup.model.alert = nil
        _ = try setup.add("Games", under: entertainment)
        setup.model.load()
        #expect(!setup.model.merge(leisure, into: entertainment))
        #expect(
            setup.model.alert?.message
                == "“Leisure” and “Entertainment” both have subcategories with 2 of the same names, including “Games”. Rename or merge one of each pair first."
        )
    }

    @Test("Merging or deleting clears the window’s Undo and Redo history (D287.4)")
    func clearsWindowHistory() throws {
        let lunch = F.expense(100, on: F.date(2026, 10, 1), category: DefaultCategoryID.groceries)
        let setup = try Setup([lunch])
        let useCases = TransactionUseCases(repository: setup.repository, categoryNames: CatalogDefaultCategoryNames())
        let window = TestWindow(useCases)
        window.history.record(try useCases.changes.remove(ids: [lunch.id]))
        #expect(window.history.canUndo)
        setup.model.onRemoval = { window.history.clearAfterRemoval() }
        #expect(setup.model.merge(groceries, into: food))
        #expect(!window.history.canUndo)
        #expect(!window.history.canRedo)
        #expect(window.history.undoTitle == nil)
    }
}

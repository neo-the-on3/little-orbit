import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The Mac Metadata manager's Categories table (#24 part 5): the flat table of both kinds, the status bar,
/// Merge for two of the same kind, inline rename, Add and Delete. Names are made up.
@MainActor
@Suite("Mac Metadata manager: Categories")
struct MetadataCategoriesViewModelTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @MainActor
    final class Setup {
        let repository: InMemoryLedgerRepository
        let model: MetadataCategoriesViewModel
        var removals = 0

        init(_ transactions: [Transaction] = []) throws {
            repository = try F.repository(transactions)
            let editing = DefaultCategoryEditingUseCase(repository: repository)
            let useCases = CategoryScreenUseCases(
                load: editing,
                edit: editing,
                categories: CategoryUseCases(repository: repository),
            )
            model = MetadataCategoriesViewModel(screen: CategoriesViewModel(useCases: useCases))
            model.screen.onRemoval = { [unowned self] in removals += 1 }
            model.load()
        }

        func add(_ name: String, under parentID: UUID? = nil, kind: CategoryKind = .expense) throws -> UUID {
            let id = try CategoryUseCases(repository: repository).saveCategory
                .add(named: name, kind: kind, parentID: parentID).id
            model.load()
            return id
        }

        func category(_ id: UUID) throws -> TransactionCategory? {
            try repository.categories().first { $0.id == id }
        }
    }

    private let food = DefaultCategoryID.food
    private let groceries = DefaultCategoryID.groceries
    private let transport = DefaultCategoryID.transport
    private let salary = DefaultCategoryID.salary
    private let interest = DefaultCategoryID.interest

    // MARK: Table

    @Test("One flat table: expense categories, then income, each parent followed by its subcategories")
    func rows() throws {
        let setup = try Setup([
            F.expense(100, on: F.date(2026, 10, 1), category: DefaultCategoryID.groceries),
            F.expense(200, on: F.date(2026, 10, 2), category: DefaultCategoryID.groceries),
            F.income(300, on: F.date(2026, 10, 3), category: DefaultCategoryID.salary),
        ])
        let restaurants = try setup.add("Restaurants", under: food)
        let rows = setup.model.rows
        #expect(rows.prefix(3).map(\.id) == [food, groceries, restaurants])
        #expect(rows.prefix(3).map(\.isSubcategory) == [false, true, true])
        let firstIncome = try #require(rows.firstIndex { $0.kind == .income })
        #expect(rows[..<firstIncome].allSatisfy { $0.kind == .expense })
        #expect(rows[firstIncome...].allSatisfy { $0.kind == .income })
        #expect(rows[firstIncome].id == salary)
        #expect(rows.first { $0.id == groceries }?.used == 2)
        #expect(rows.first { $0.id == food }?.used == 0, "A parent counts only its own transactions (D303)")
        #expect(rows.first { $0.id == salary }?.kindName == "Income")
        #expect(rows.first { $0.id == groceries }?.hue == .orange, "A subcategory shows its parent’s colour")
    }

    @Test("VoiceOver reads a subcategory row with its parent, as the iOS form does (UI Designer, #169 point 3)")
    func spokenNames() throws {
        let setup = try Setup()
        let rows = setup.model.rows
        #expect(rows.first { $0.id == groceries }?.spokenName == "Groceries, under Food & Dining")
        #expect(rows.first { $0.id == food }?.spokenName == "Food & Dining", "A top-level row reads its name")
        #expect(rows.first { $0.id == salary }?.spokenName == "Salary")
    }

    @Test("Archived categories leave the table and are listed under Archived, both kinds")
    func archived() throws {
        let setup = try Setup()
        #expect(setup.model.screen.archive(groceries))
        #expect(setup.model.screen.archive(interest))
        setup.model.load()
        #expect(!setup.model.rows.contains { $0.id == groceries || $0.id == interest })
        #expect(setup.model.archivedRows.map(\.id) == [groceries, interest])
        #expect(
            setup.model.archivedRows.first?.subtitle == "Food & Dining",
            "An archived subcategory names its parent",
        )
    }

    @Test("Unarchiving a subcategory under an archived parent asks first, on the Mac too (D302)")
    func unarchivePrompt() throws {
        let setup = try Setup()
        #expect(setup.model.screen.archive(food))
        setup.model.load()
        setup.model.screen.requestUnarchive(groceries)
        let prompt = try #require(setup.model.screen.unarchivePrompt)
        #expect(prompt.title == "Unarchive “Groceries”?")
        #expect(
            prompt.message
                == "Its parent, “Food & Dining”, is archived too, so it’s unarchived as well. Other subcategories in “Food & Dining” stay archived."
        )
        setup.model.screen.confirmUnarchive()
        setup.model.load()
        #expect(setup.model.rows.prefix(2).map(\.id) == [food, groceries])
    }

    @Test("A selected category that’s archived or deleted leaves the selection")
    func selectionPruned() throws {
        let setup = try Setup()
        setup.model.selection = [groceries, transport]
        #expect(setup.model.screen.archive(groceries))
        setup.model.load()
        #expect(setup.model.selection == [transport])
    }

    // MARK: Status bar and Merge

    @Test("The status bar counts the selection and names both kinds when they’re mixed")
    func statusText() throws {
        let setup = try Setup()
        #expect(setup.model.statusText.isEmpty)
        setup.model.selection = [food]
        #expect(setup.model.statusText == "1 selected")
        setup.model.selection = [food, transport]
        #expect(setup.model.statusText == "2 selected")
        setup.model.selection = [food, salary]
        #expect(setup.model.statusText == "2 selected · 1 expense, 1 income")
        setup.model.selection = [food, transport, salary]
        #expect(setup.model.statusText == "3 selected · 2 expense, 1 income")
    }

    @Test("Merge needs exactly two categories of the same kind, with a tooltip saying why not")
    func mergeAvailability() throws {
        let setup = try Setup()
        setup.model.selection = [food]
        #expect(setup.model.mergeAvailability == .needsTwo)
        #expect(setup.model.mergeHelp == "Select two categories of the same kind to merge.")
        setup.model.selection = [food, salary]
        #expect(setup.model.mergeAvailability == .mixedKinds)
        #expect(setup.model.mergeHelp == "Merge is only available for categories of the same kind.")
        setup.model.startMerge()
        #expect(setup.model.merge == nil)
        setup.model.selection = [food, transport, DefaultCategoryID.housing]
        #expect(setup.model.mergeAvailability == .needsTwo, "A merge is one pair, all or nothing (D287.4)")
        setup.model.selection = [salary, interest]
        #expect(setup.model.mergeAvailability == .available)
        #expect(setup.model.mergeHelp == nil)
    }

    @Test("Merge 2 Categories keeps the more used one by default and merges the other into it (D287.4)")
    func mergeSheet() throws {
        let setup = try Setup([
            F.expense(100, on: F.date(2026, 10, 1), category: DefaultCategoryID.transport),
            F.expense(200, on: F.date(2026, 10, 2), category: DefaultCategoryID.shopping),
            F.expense(300, on: F.date(2026, 10, 3), category: DefaultCategoryID.shopping),
        ])
        let shopping = DefaultCategoryID.shopping
        setup.model.selection = [shopping, transport]
        setup.model.startMerge()
        let merge = try #require(setup.model.merge)
        #expect(merge.title == "Merge 2 Categories")
        #expect(
            merge.message
                == "Transport and Shopping are both expense categories. Choose the one to keep; the other’s transactions move to it and it is deleted.",
            "Names follow the table’s order",
        )
        #expect(merge.keepOptions.map(\.id) == [transport, shopping])
        #expect(merge.keptID == shopping, "Shopping has more transactions")
        #expect(
            merge.footnote == "1 transaction will use Shopping. Transport is then deleted. Merging can’t be undone."
        )
        merge.keptID = transport
        #expect(
            merge.footnote == "2 transactions will use Transport. Shopping is then deleted. Merging can’t be undone."
        )
        #expect(merge.confirm())
        #expect(try setup.category(shopping) == nil)
        #expect(try setup.repository.transactions().allSatisfy { $0.categoryID == transport })
        #expect(setup.removals == 1, "This window’s Undo is cleared after a merge (D287.4)")
        setup.model.load()
        #expect(setup.model.selection == [transport])
    }

    @Test("On a tie, Keep defaults to the category selected first, not the first in the table (D304.5)")
    func mergeTieKeepsFirstSelected() throws {
        let setup = try Setup()
        let shopping = DefaultCategoryID.shopping
        setup.model.selection = [shopping]
        setup.model.selection.insert(transport)
        setup.model.startMerge()
        var merge = try #require(setup.model.merge)
        #expect(merge.keepOptions.map(\.id) == [transport, shopping], "The pop-up keeps the table’s order")
        #expect(merge.keptID == shopping, "Shopping was selected first")

        setup.model.selection = [transport]
        setup.model.selection.insert(shopping)
        setup.model.startMerge()
        merge = try #require(setup.model.merge)
        #expect(merge.keptID == transport, "Transport was selected first")
    }

    @Test("Selection order survives deselecting and reselecting, and rows selected together follow the table")
    func selectionOrder() throws {
        let setup = try Setup()
        let shopping = DefaultCategoryID.shopping
        let housing = DefaultCategoryID.housing
        setup.model.selection = [shopping, transport]
        #expect(setup.model.selectionOrder == [transport, shopping], "Selected at once: the table’s order")
        setup.model.selection.insert(housing)
        setup.model.selection.remove(transport)
        #expect(setup.model.selectionOrder == [shopping, housing])
        setup.model.selection.insert(transport)
        #expect(setup.model.selectionOrder == [shopping, housing, transport])
        setup.model.selection = []
        #expect(setup.model.selectionOrder.isEmpty)
    }

    @Test("The more-used category is still kept whichever was selected first (D304.5)")
    func mergeMoreUsedBeatsSelectionOrder() throws {
        let setup = try Setup([F.expense(100, on: F.date(2026, 10, 1), category: DefaultCategoryID.transport)])
        let shopping = DefaultCategoryID.shopping
        setup.model.selection = [shopping]
        setup.model.selection.insert(transport)
        setup.model.startMerge()
        #expect(setup.model.merge?.keptID == transport)
    }

    @Test("Merge offers only the directions the ledger allows (D291.2)")
    func mergeDirections() throws {
        let setup = try Setup([F.expense(100, on: F.date(2026, 10, 1), category: DefaultCategoryID.groceries)])
        setup.model.selection = [food, groceries]
        setup.model.startMerge()
        #expect(
            setup.model.merge?.keepOptions.map(\.id) == [food],
            "A category never merges into its own subcategory, even when the subcategory is used more",
        )
        #expect(setup.model.merge?.keptID == food)

        let parking = try setup.add("Parking", under: transport)
        setup.model.selection = [food, parking]
        setup.model.startMerge()
        #expect(
            setup.model.merge?.keepOptions.map(\.id) == [food],
            "A parent with subcategories never goes under a subcategory",
        )
    }

    @Test("Merging a parent says where its subcategories go (D301)")
    func mergeFootnoteSubcategories() throws {
        let setup = try Setup()
        let leisure = try setup.add("Leisure")
        _ = try setup.add("Movies", under: leisure)
        _ = try setup.add("Games", under: leisure)
        setup.model.selection = [DefaultCategoryID.entertainment, leisure]
        setup.model.startMerge()
        let merge = try #require(setup.model.merge)
        merge.keptID = DefaultCategoryID.entertainment
        #expect(
            merge.footnote
                == "0 transactions will use Entertainment. Leisure is then deleted. Its 2 subcategories move to “Entertainment”. Merging can’t be undone."
        )
    }

    @Test("A same-named subcategory refuses the merge on the sheet, which stays open (D291.1)")
    func mergeClash() throws {
        let setup = try Setup()
        let leisure = try setup.add("Leisure")
        _ = try setup.add("Movies", under: leisure)
        let entertainment = DefaultCategoryID.entertainment
        _ = try setup.add("Movies", under: entertainment)
        setup.model.selection = [entertainment, leisure]
        setup.model.startMerge()
        let merge = try #require(setup.model.merge)
        merge.keptID = entertainment
        #expect(!merge.confirm())
        #expect(merge.alert?.title == "Can’t Merge Categories")
        #expect(
            merge.alert?.message
                == "“Leisure” and “Entertainment” both have a subcategory named “Movies”. Rename or merge one of them first."
        )
        #expect(setup.model.screen.alert == nil, "Only the sheet shows it")
        #expect(try setup.category(leisure) != nil)
        #expect(setup.removals == 0)
    }

    @Test("Merging two income categories reads the income targets")
    func mergeIncome() throws {
        let setup = try Setup([F.income(300, on: F.date(2026, 10, 3), category: DefaultCategoryID.salary)])
        setup.model.selection = [salary, interest]
        setup.model.startMerge()
        let merge = try #require(setup.model.merge)
        #expect(merge.message.hasPrefix("Salary and Interest are both income categories."))
        #expect(merge.keepOptions.map(\.id) == [salary, interest])
        #expect(merge.keptID == salary)
        #expect(merge.confirm())
        #expect(try setup.category(interest) == nil)
    }

    // MARK: Rename

    @Test("Renaming in the row saves on Return, and an unchanged name just ends the rename")
    func rename() throws {
        let setup = try Setup()
        setup.model.beginRename(DefaultCategoryID.entertainment)
        #expect(setup.model.selection == [DefaultCategoryID.entertainment])
        #expect(setup.model.renameText == "Entertainment")
        #expect(
            setup.model.statusText
                == "Return saves · Esc cancels · names must be unique among categories of the same kind",
            "A top-level name is unique within its kind (D299, D304.7)",
        )
        setup.model.renameText = "Entertainment & Hobbies"
        #expect(setup.model.commitRename())
        #expect(setup.model.renaming == nil)
        #expect(try setup.category(DefaultCategoryID.entertainment)?.name == "Entertainment & Hobbies")
        #expect(setup.model.rows.contains { $0.name == "Entertainment & Hobbies" })

        setup.model.beginRename(transport)
        #expect(setup.model.commitRename())
        #expect(setup.model.renaming == nil)
    }

    @Test("A subcategory’s rename hint says its name is unique within the same parent (D304.7)")
    func renameHintSubcategory() throws {
        let setup = try Setup()
        setup.model.beginRename(groceries)
        #expect(
            setup.model.statusText == "Return saves · Esc cancels · names must be unique within the same parent"
        )
    }

    @Test("A name error keeps the row editing and shows in the status bar (D295.4); Esc keeps the old name")
    func renameError() throws {
        let setup = try Setup()
        setup.model.beginRename(transport)
        setup.model.renameText = " housing "
        #expect(setup.model.statusText == "There’s already a category named “Housing” here.")
        #expect(!setup.model.commitRename())
        #expect(setup.model.renaming != nil)
        setup.model.renameText = ""
        #expect(setup.model.statusText == "Enter a name.")
        setup.model.cancelRename()
        #expect(setup.model.renaming == nil)
        #expect(try setup.category(transport)?.name == "Transport")
        #expect(setup.model.statusText == "1 selected")
    }

    @Test("A top-level name is checked within its kind, so an income category can share an expense name (D299)")
    func renameAcrossKinds() throws {
        let setup = try Setup()
        setup.model.beginRename(interest)
        setup.model.renameText = "Transport"
        #expect(setup.model.commitRename())
        #expect(try setup.category(interest)?.name == "Transport")
    }

    // MARK: Add, edit and delete

    @Test("Add opens a new category of the chosen kind, or a subcategory under the selected category’s parent")
    func add() throws {
        let setup = try Setup()
        setup.model.openNewCategory(.income)
        let income = try #require(setup.model.screen.editor)
        #expect(income.kind == .income)
        #expect(!income.isSubcategory)
        #expect(income.title == "New Category")

        setup.model.selection = []
        #expect(setup.model.subcategoryParent == nil)
        setup.model.selection = [groceries]
        #expect(setup.model.subcategoryParent?.id == food)
        setup.model.selection = [salary]
        #expect(setup.model.subcategoryParent?.id == salary)
        setup.model.openNewSubcategory()
        let sub = try #require(setup.model.screen.editor)
        #expect(sub.isSubcategory)
        #expect(sub.kind == .income)
        #expect(sub.parentID == salary)
        #expect(sub.kindValue == "Income (from parent)")
        sub.name = "Bonus"
        #expect(sub.save())
        #expect(try setup.repository.categories().contains { $0.name == "Bonus" && $0.parentID == salary })
    }

    @Test("Edit Category… opens the row’s editor and ends a rename")
    func edit() throws {
        let setup = try Setup()
        setup.model.beginRename(transport)
        setup.model.openEditor(for: food)
        #expect(setup.model.renaming == nil)
        #expect(setup.model.screen.editor?.categoryID == food)
        #expect(setup.model.screen.editor?.title == "Edit Category")
    }

    @Test("Delete asks about the one selected category; Move To lists only its own kind (D19, D291.4)")
    func delete() throws {
        let setup = try Setup([F.income(300, on: F.date(2026, 10, 3), category: DefaultCategoryID.salary)])
        setup.model.selection = [food, salary]
        setup.model.requestDelete()
        #expect(setup.model.screen.deletePrompt == nil, "Delete works on one category")
        setup.model.selection = [salary]
        setup.model.requestDelete()
        let prompt = try #require(setup.model.screen.deletePrompt)
        #expect(prompt.title == "Delete “Salary”?")
        setup.model.startMove(salary)
        #expect(setup.model.screen.deletePrompt == nil)
        let choice = try #require(setup.model.moveChoice)
        #expect(!choice.rows.isEmpty)
        #expect(choice.rows.allSatisfy { setup.model.screen.category($0.id)?.kind == .income })
        choice.targetID = interest
        #expect(choice.confirm())
        #expect(try setup.category(salary) == nil)
        #expect(try setup.repository.transactions().first?.categoryID == interest)
        #expect(setup.removals == 1)
    }
}

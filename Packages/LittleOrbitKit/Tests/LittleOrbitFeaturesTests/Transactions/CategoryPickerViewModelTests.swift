import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The transaction form's category picker (#24 frames 16:7540 and 16:7702): Uncategorised, the transaction's
/// kind only, archived hidden, search, and inline create that keeps the form's fields (AC 5). Names are made up.
@MainActor
@Suite("Transaction form category picker")
struct CategoryPickerViewModelTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private let food = DefaultCategoryID.food
    private let groceries = DefaultCategoryID.groceries
    private let shopping = DefaultCategoryID.shopping

    /// Counts the store reads, so the tests can show the sheet reads once when it opens and again only after
    /// Create, never while it's drawn.
    @MainActor
    final class CountingLoad: LoadCategoriesUseCase {
        let real: any LoadCategoriesUseCase
        var reads = 0
        var fails = false

        init(_ real: any LoadCategoriesUseCase) {
            self.real = real
        }

        func listing() throws -> CategoryListing {
            reads += 1
            if fails {
                throw LedgerValidationError.missingCategory
            }
            return try real.listing()
        }
    }

    @MainActor
    final class Setup {
        let repository: InMemoryLedgerRepository
        let load: CountingLoad
        let useCases: CategoryPickingUseCases
        var changes = 0

        init(_ transactions: [Transaction] = []) throws {
            repository = try F.repository(transactions)
            let editing = DefaultCategoryEditingUseCase(repository: repository)
            load = CountingLoad(editing)
            useCases = CategoryPickingUseCases(load: load, edit: editing)
        }

        func picker(_ kind: CategoryKind = .expense, selection: UUID? = nil) -> CategoryPickerViewModel {
            CategoryPickerViewModel(kind: kind, selection: selection, useCases: useCases) { [unowned self] in
                changes += 1
            }
        }

        func form(_ mode: TransactionFormMode = .new(accountID: F.savingsID)) -> TransactionFormViewModel {
            TransactionFormViewModel(
                useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
                mode: mode,
                locale: F.india,
                timeZone: F.zone,
                now: { F.now },
                categoryPicking: useCases,
                categoriesChanged: { [unowned self] in changes += 1 },
            )
        }
    }

    @Test("An expense lists Uncategorised, then only expense categories with their subcategories (16:7540)")
    func expenseList() throws {
        let setup = try Setup([F.expense(25, on: F.date(2026, 10, 1), category: groceries)])
        let picker = setup.picker()
        #expect(picker.title == "Category")
        #expect(picker.searchPrompt == "Search or create")
        #expect(picker.showsUncategorised)
        #expect(picker.uncategorisedTitle == "Uncategorised")
        #expect(picker.uncategorisedSubtitle == "No category")
        #expect(picker.sectionTitle == "Expense")
        let first = try #require(picker.groups.first)
        #expect(first.parent.name == "Food & Dining")
        #expect(first.parent.subtitle == "Expense · 1 subcategory")
        #expect(first.subcategories.map(\.name) == ["Groceries"])
        #expect(first.subcategories.first?.subtitle == "Expense · 1 transaction")
        #expect(first.subcategories.first?.hue == .orange, "A subcategory shows its parent’s colour")
        let names = picker.groups.map(\.parent.name)
        #expect(!names.contains("Salary"), "Income categories aren’t offered on an expense")
        #expect(picker.createName == nil)
    }

    @Test("Rows reuse the Categories screen’s subtitle: own use only, with the kind first (D303)")
    func subtitlesMatchCategoriesScreen() throws {
        let transactions = [
            F.expense(25, on: F.date(2026, 10, 1), category: groceries),
            F.expense(40, on: F.date(2026, 10, 2), category: food),
        ]
        let picker = try Setup(transactions).picker()
        let parent = try #require(picker.groups.first { $0.id == food }).parent
        #expect(parent.subtitle == "Expense · 1 transaction · 1 subcategory", "Groceries’ use isn’t Food’s own")
        let screen = try CategoriesViewModelTests.Setup(transactions).model
        let rows = screen.groups.flatMap { [$0.parent] + $0.subcategories }
        for group in picker.groups {
            for row in [group.parent] + group.subcategories {
                #expect(row.subtitle == rows.first { $0.id == row.id }?.subtitle)
            }
        }
    }

    @Test("An income lists only income categories")
    func incomeList() throws {
        let picker = try Setup().picker(.income)
        #expect(picker.sectionTitle == "Income")
        #expect(picker.groups.map(\.parent.name).first == "Salary")
        #expect(!picker.groups.contains { $0.parent.name == "Food & Dining" })
    }

    @Test("Archived categories are hidden, except the transaction’s own, which shows under Archived, checked")
    func archived() throws {
        let setup = try Setup()
        try setup.repository.archiveCategory(id: shopping, archived: true)
        let fresh = setup.picker()
        #expect(!fresh.groups.contains { $0.parent.id == shopping })
        #expect(fresh.archivedRow == nil)
        let editing = setup.picker(selection: shopping)
        #expect(!editing.groups.contains { $0.parent.id == shopping })
        #expect(editing.archivedRow?.name == "Shopping")
        #expect(editing.archivedTitle == "Archived")
        #expect(editing.selection == shopping)
    }

    @Test("Search matches any part of a name, ignoring case and accents, and keeps a match’s parent")
    func search() throws {
        let setup = try Setup()
        _ = try CategoryUseCases(repository: setup.repository).saveCategory
            .add(
                named: "Café visits",
                kind: .expense,
                parentID: food,
            )
        let picker = setup.picker()
        picker.query = "CERI"
        #expect(picker.groups.map(\.parent.name) == ["Food & Dining"])
        #expect(picker.groups.first?.subcategories.map(\.name) == ["Groceries"])
        #expect(!picker.showsUncategorised, "Uncategorised hides while typing (16:7702)")
        picker.query = "cafe"
        #expect(picker.groups.first?.subcategories.map(\.name) == ["Café visits"])
        picker.query = "dining"
        #expect(picker.groups.first?.subcategories.count == 2, "A matching parent shows all its subcategories")
    }

    @Test("A typed name nothing matches offers Create; an existing name, trimmed and in any case, doesn’t")
    func createRow() throws {
        let picker = try Setup().picker()
        picker.query = "  Pet care "
        #expect(picker.createName == "Pet care")
        #expect(picker.createTitle == "Create “Pet care”")
        #expect(picker.createDetail == "Expense category")
        #expect(picker.groups.isEmpty)
        picker.query = "groceries "
        #expect(picker.createName == nil, "An existing subcategory is reused, not duplicated")
        picker.query = "FOOD & DINING"
        #expect(picker.createName == nil)
        picker.query = "   "
        #expect(picker.createName == nil)
        #expect(try Setup().picker(.income).createDetail == "Income category")
    }

    @Test("Create adds a top-level category of the transaction’s kind, checks it and clears the search (AC 5)")
    func create() throws {
        let setup = try Setup()
        let picker = setup.picker()
        picker.query = "Pet care"
        #expect(picker.create())
        let saved = try #require(try setup.repository.categories().first { $0.name == "Pet care" })
        #expect(saved.kind == .expense)
        #expect(saved.parentID == nil)
        #expect(saved.iconName == "tag.fill", "The icon Add Category starts with")
        #expect(saved.colorHex == CategoryHue.gray.hex)
        #expect(picker.selection == saved.id)
        #expect(picker.query.isEmpty)
        #expect(picker.groups.contains { $0.parent.id == saved.id })
        #expect(setup.changes == 1, "Other windows reload")
    }

    @Test("Create on an income makes an income category")
    func createIncome() throws {
        let setup = try Setup()
        let picker = setup.picker(.income)
        picker.query = "Freelance"
        #expect(picker.create())
        #expect(try setup.repository.categories().first { $0.name == "Freelance" }?.kind == .income)
    }

    @Test("A name the ledger refuses shows “Couldn’t Save Changes” with why, and adds nothing")
    func createRefused() throws {
        let setup = try Setup()
        let pets = try CategoryUseCases(repository: setup.repository).saveCategory
            .add(
                named: "Pet care",
                kind: .expense,
                parentID: nil,
            )
        try setup.repository.archiveCategory(id: pets.id, archived: true)
        let picker = setup.picker()
        picker.query = "pet care"
        #expect(picker.createName == "pet care", "The archived one isn’t shown, so Create is offered")
        let before = try setup.repository.categories().count
        #expect(!picker.create())
        #expect(picker.alert?.title == "Couldn’t Save Changes")
        #expect(picker.alert?.message == "There’s already a category named “pet care” here.")
        #expect(try setup.repository.categories().count == before)
        #expect(setup.changes == 0)
        picker.query = String(repeating: "a", count: 101)
        #expect(!picker.create())
        #expect(picker.alert?.message == "Use 100 characters or fewer.")
    }

    @Test("A list that can’t be read shows “Couldn’t Load Categories” / “Try again.” (D299)")
    func loadFails() throws {
        let setup = try Setup()
        setup.load.fails = true
        let picker = setup.picker()
        #expect(picker.alert?.title == "Couldn’t Load Categories")
        #expect(picker.alert?.message == "Try again.")
        #expect(picker.groups.isEmpty)
        #expect(picker.showsUncategorised, "Uncategorised still works")
    }

    @Test("The sheet reads the store once when it opens and once after Create, never while it’s drawn")
    func readsOnce() throws {
        let setup = try Setup()
        let picker = setup.picker()
        #expect(setup.load.reads == 1)
        for query in ["", "g", "gr", "Pet care"] {
            picker.query = query
            _ = picker.groups
            _ = picker.archivedRow
            _ = picker.createName
            _ = picker.showsUncategorised
            _ = picker.selectedCategory
        }
        picker.select(groceries)
        #expect(setup.load.reads == 1)
        #expect(picker.create())
        #expect(setup.load.reads == 2)
        _ = picker.groups
        #expect(setup.load.reads == 2)
    }

    @Test("The form opens the picker for its kind with its category checked; a transfer has none")
    func formMakesPicker() throws {
        let setup = try Setup()
        let form = setup.form()
        #expect(form.hasCategoryPicker)
        #expect(setup.load.reads == 0, "The form doesn’t read categories for the picker until it opens")
        form.categoryID = groceries
        let picker = try #require(form.makeCategoryPicker())
        #expect(picker.kind == .expense)
        #expect(picker.selection == groceries)
        form.type = .income
        #expect(form.makeCategoryPicker()?.kind == .income)
        form.type = .transfer
        #expect(form.makeCategoryPicker() == nil)
        let plain = TransactionFormViewModel(
            useCases: TransactionUseCases(repository: setup.repository, categoryNames: CatalogDefaultCategoryNames()),
            mode: .new(accountID: F.savingsID),
        )
        #expect(!plain.hasCategoryPicker, "Without the use cases the menu picker stays (macOS)")
        #expect(plain.makeCategoryPicker() == nil)
    }

    @Test("Creating “Pet care” from the form keeps the amount, payee and notes, and saves with it (AC 5)")
    func inlineCreateKeepsForm() throws {
        let setup = try Setup()
        let form = setup.form()
        form.press(.digit(4))
        form.press(.digit(5))
        form.payeeText = "Corner Bakery"
        form.note = "Weekly treat"
        let picker = try #require(form.makeCategoryPicker())
        picker.query = "Pet care"
        #expect(picker.create())
        form.chooseCategory(from: picker)
        #expect(form.categoryName == "Pet care")
        #expect(form.amount == 45)
        #expect(form.payeeText == "Corner Bakery")
        #expect(form.note == "Weekly treat")
        #expect(form.save() != nil)
        let pets = try #require(try setup.repository.categories().first { $0.name == "Pet care" })
        #expect(try setup.repository.transactions().first?.categoryID == pets.id)
    }

    @Test("Done with Uncategorised clears the category; Cancel, not calling chooseCategory, keeps it")
    func uncategorised() throws {
        let setup = try Setup()
        let form = setup.form()
        form.categoryID = groceries
        let picker = try #require(form.makeCategoryPicker())
        picker.select(nil)
        #expect(form.categoryID == groceries, "Nothing changes on the form until Done")
        form.chooseCategory(from: picker)
        #expect(form.categoryID == nil)
        #expect(form.categoryName == "Uncategorised")
    }

    @Test("A category chosen in the picker isn’t replaced by a later payee’s last-used one")
    func pickedCategoryStays() throws {
        let setup = try Setup()
        try setup.repository.savePayee(Payee(name: "Parcel Point", defaultCategoryID: shopping))
        let form = setup.form()
        let picker = try #require(form.makeCategoryPicker())
        picker.select(groceries)
        form.chooseCategory(from: picker)
        form.payeeText = "Parcel Point"
        #expect(form.categoryID == groceries)
    }
}

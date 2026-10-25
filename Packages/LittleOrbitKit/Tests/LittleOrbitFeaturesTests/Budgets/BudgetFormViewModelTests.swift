import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// The New Budget and Edit Budget form (#25 design frames; D307.1, D307.5–D307.8, D151, D300.1).
@MainActor
@Suite("Budget form (#25)")
struct BudgetFormViewModelTests {
    typealias T = TransactionFeatureFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFeatureFixture  // swiftlint:disable:this type_name

    private let repository: InMemoryLedgerRepository
    private let updates = LedgerUpdates()
    private let window: TestWindow

    init() throws {
        try self.init(budgets: [])
    }

    private init(budgets: [Budget]) throws {
        repository = try B.repository(budgets)
        window = TestWindow(
            TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
            updates: updates,
        )
    }

    private static func with(_ budgets: [Budget]) throws -> Self {
        try Self(budgets: budgets)
    }

    private func form(_ mode: BudgetFormViewModel.Mode = .new) throws -> BudgetFormViewModel {
        let budgets = DefaultBudgetUseCases(repository: repository, now: { T.now })
        let history = window.history
        return try BudgetFormViewModel(
            mode: mode,
            useCases: BudgetFormUseCases(
                budgets: budgets,
                changes: budgets,
                categories: DefaultCategoryEditingUseCase(repository: repository),
            ),
            today: T.today,
            locale: T.india,
            defaultCurrency: "INR",
            updates: updates,
            history: { history },
        )
    }

    private func fill(_ form: BudgetFormViewModel, name: String = "Eating out", limit: String = "8,000") {
        form.name = name
        form.limitText = limit
        form.toggleCategory(B.eatingOutID)
    }

    // MARK: Opening

    @Test("A new budget starts today, monthly, in the default currency, with nothing to save yet")
    func newDefaults() throws {
        let form = try form()
        #expect(form.title == "New Budget")
        #expect(form.currencyCode == "INR")
        #expect(form.startDay == T.today)
        #expect(form.recurrence == .monthly)
        #expect(!form.carriesOverUnspent && !form.carriesOverOverspending)
        #expect(form.categoriesSummary == "None")
        #expect(!form.canSave)
        #expect(!form.hasUnsavedEdits, "An untouched form closes without asking (D300.1)")
        #expect(form.nameError == nil && form.limitError == nil && form.categoriesError == nil)
    }

    @Test("D309.4: the placeholders are “Name” and the currency’s zero, “₹0”")
    func placeholders() throws {
        let form = try form()
        #expect(BudgetText.namePrompt == "Name")
        #expect(form.limitPrompt == "₹0")
        form.currencyCode = "JPY"
        #expect(form.limitPrompt.hasSuffix("0") && !form.limitPrompt.contains("₹"))
    }

    @Test("Edit Budget shows the budget, its current period's limit, and Save stays off until something changes")
    func editOpens() throws {
        let budget = B.budget("Eating out", limit: 8_000, recurrence: .custom(every: 3, unit: .week))
        let form = try Self.with([budget]).form(.edit(budget.id))
        #expect(form.title == "Edit Budget")
        #expect(form.name == "Eating out")
        #expect(form.limitText == "8,000.00")
        #expect(form.repeatChoice == .custom && form.customCount == 3 && form.customUnit == .week)
        #expect(form.categoriesSummary == "Eating out")
        #expect(!form.hasUnsavedEdits && !form.canSave)
        form.carriesOverUnspent = true
        #expect(form.hasUnsavedEdits && form.canSave)
        form.carriesOverUnspent = false
        #expect(!form.hasUnsavedEdits, "Changing a value back is no edit")
    }

    @Test("Editing a budget that's gone can't open")
    func editMissing() throws {
        #expect(throws: LedgerValidationError.missingBudget) {
            _ = try form(.edit(UUID()))
        }
    }

    // MARK: Validation

    @Test("Frame: validation errors under each field, Save off, and no banner (ruling 6)")
    func threeErrors() throws {
        let form = try form()
        form.name = "x"
        form.name = "  "
        form.limitText = "0"
        #expect(form.nameError == "Enter a name.")
        #expect(form.limitError == "Enter a limit above ₹0.")
        #expect(
            form.categoriesError == "Choose at least one expense category.",
            "Shown once name and limit are edited",
        )
        #expect(!form.canSave)
        form.name = "Eating out"
        form.limitText = "8000"
        #expect(form.nameError == nil && form.limitError == nil && !form.canSave)
        form.toggleCategory(B.eatingOutID)
        #expect(form.categoriesError == nil && form.canSave)
    }

    @Test(
        "A limit that can't be read says how to type it",
        arguments: [
            ("abc", "Enter a limit like 1,25,000.00."),
            ("12.345", "INR amounts can have up to 2 decimal places."),
            ("-500", "Enter a limit above ₹0."),
        ],
    )
    func limitErrors(text: String, message: String) throws {
        let form = try form()
        form.limitText = text
        #expect(form.limitError == message)
    }

    @Test("A currency with no decimals says so")
    func noDecimals() throws {
        let form = try form()
        form.currencyCode = "JPY"
        form.limitText = "10.5"
        #expect(form.limitError == "JPY amounts have no decimal places.")
    }

    @Test("D307.6: another budget's name, trimmed and ignoring case, quotes the stored name")
    func duplicateName() throws {
        let form = try Self.with([B.budget("Eating out", limit: 100)]).form()
        fill(form, name: "  eating OUT ")
        #expect(form.nameError == "There’s already a budget named “Eating out”.")
        #expect(!form.canSave)
    }

    @Test("D307.6: a budget can change the case of its own name")
    func caseOnlyRename() throws {
        let budget = B.budget("Eating out", limit: 100)
        let form = try Self.with([budget]).form(.edit(budget.id))
        form.name = "EATING OUT"
        #expect(form.nameError == nil && form.canSave)
    }

    @Test("D307.6: a name taken in another window after the form opened shows under the name")
    func duplicateOnSave() throws {
        let form = try form()
        fill(form)
        try repository.saveBudget(B.budget("eating out", limit: 100, categories: [B.shoppingID]))
        #expect(form.save() == .notSaved)
        #expect(form.nameError == "There’s already a budget named “Eating out”.")
        #expect(!form.canSave)
        form.name = "Dining"
        #expect(form.canSave)
    }

    @Test("A budget deleted in another window can't be saved, and says so")
    func deletedOnSave() throws {
        let budget = B.budget("Eating out", limit: 100)
        let setup = try Self.with([budget])
        let form = try setup.form(.edit(budget.id))
        form.limitText = "200"
        try setup.repository.deleteBudget(id: budget.id)
        #expect(form.save() == .notSaved)
        #expect(form.alert?.title == "Couldn’t Save Changes")
        #expect(form.alert?.message == "This budget no longer exists.", "D309.3")
    }

    @Test("A custom repeat stays every 1–99 (S16)")
    func customRange() throws {
        let form = try form()
        form.repeatChoice = .custom
        form.customCount = 0
        #expect(form.customCount == 1)
        form.customCount = 120
        #expect(form.customCount == 99)
        #expect(form.recurrence == .custom(every: 99, unit: .month))
    }

    // MARK: Categories

    @Test("Frame: only unarchived expense categories, each parent followed by its subcategories")
    func categoryOptions() throws {
        let form = try form()
        let listing = try DefaultCategoryEditingUseCase(repository: repository).listing()
        let options = form.categoryOptions
        let expense = listing.categories.filter { $0.kind == .expense && !$0.isArchived }
        #expect(Set(options.map(\.id)) == Set(expense.map(\.id)))
        let parent = try #require(expense.first { !listing.subcategories(of: $0.id).isEmpty })
        let index = try #require(options.firstIndex { $0.id == parent.id })
        let count = listing.subcategories(of: parent.id).count
        #expect(options[index].subtitle == (count == 1 ? "1 subcategory" : "\(count) subcategories"))
        #expect(options[index + 1].isSubcategory)
        #expect(listing.categories.contains { $0.kind == .income })
        #expect(form.hasCategoriesToPick)
    }

    @Test("Picking a parent includes its subcategories, which can't be picked on their own")
    func parentIncludesChildren() throws {
        let form = try form()
        let listing = try DefaultCategoryEditingUseCase(repository: repository).listing()
        let parent = try #require(
            listing.categories.first { $0.kind == .expense && !listing.subcategories(of: $0.id).isEmpty }
        )
        let child = try #require(listing.subcategories(of: parent.id).first)
        form.toggleCategory(child.id)
        #expect(form.categoryIDs == [child.id])
        form.toggleCategory(parent.id)
        #expect(form.categoryIDs == [parent.id], "The parent stands for the subcategory now")
        #expect(form.isSelected(child.id) && form.isIncludedByParent(child.id))
        form.toggleCategory(child.id)
        #expect(form.categoryIDs == [parent.id], "An included subcategory can't be unpicked on its own")
        #expect(form.categoriesHeader == "Expense categories · 1 selected")
    }

    @Test("Frame: the Categories row lists the picked ones in the tree's order, or “None”")
    func categoriesSummary() throws {
        let form = try form()
        form.toggleCategory(B.shoppingID)
        form.toggleCategory(B.eatingOutID)
        #expect(form.categoriesSummary == "Eating out, Shopping trips")
        #expect(form.categoriesHeader == "Expense categories · 2 selected")
        form.toggleCategory(B.shoppingID)
        form.toggleCategory(B.eatingOutID)
        #expect(form.categoriesSummary == "None")
        #expect(form.categoriesError == "Choose at least one expense category.")
    }

    @Test("An archived category stays listed while the budget has it picked")
    func archivedPicked() throws {
        var archived = try #require(B.categories.first)
        archived.isArchived = true
        try repository.saveCategory(archived)
        let budget = B.budget("Eating out", limit: 100)
        try repository.saveBudget(budget)
        #expect(try form().categoryOptions.contains { $0.id == archived.id } == false)
        let edit = try form(.edit(budget.id))
        #expect(edit.categoryOptions.contains { $0.id == archived.id })
    }

    // MARK: Repeat

    @Test("Frame: Repeat – custom, every 3 weeks lists this period and the two after it")
    func nextPeriods() throws {
        let form = try form()
        form.startDay = CalendarDay(year: 2026, month: 10, day: 1)
        form.repeatChoice = .custom
        form.customCount = 3
        form.customUnit = .week
        let periods = form.nextPeriods
        #expect(periods.map(\.isCurrent) == [true, false, false])
        #expect(periods.map(\.id) == [0, 1, 2])
        #expect(periods.allSatisfy { !$0.dates.isEmpty })
        #expect(form.repeatSummary == "Every 3 weeks")
        #expect(form.periodFootnote == "Each period starts on the start day and ends the day before the next one.")
        form.customUnit = .month
        #expect(form.periodFootnote.hasSuffix("31 Mar–29 Apr."))
    }

    @Test("D309.5: “Week” after “Every 1”, “Weeks” after “Every 3”, each its own entry; Repeat keeps “Every week”")
    func unitLabels() throws {
        // A plural variation that leaves out its number fails CompileXCStrings, so each word is its own entry.
        let catalog = try StringCatalogTests.entries()
        for word in ["Day", "Days", "Week", "Weeks", "Month", "Months", "Year", "Years"] {
            #expect(catalog[word] == [word], "\(word) is one entry with its English value")
        }
        let form = try form()
        form.repeatChoice = .custom
        form.customCount = 1
        #expect(BudgetRecurrenceUnit.allCases.map { form.unitTitle($0) } == ["Day", "Week", "Month", "Year"])
        form.customUnit = .week
        #expect(form.repeatSummary == "Every week")
        form.customCount = 3
        #expect(BudgetRecurrenceUnit.allCases.map { form.unitTitle($0) } == ["Days", "Weeks", "Months", "Years"])
        #expect(form.repeatSummary == "Every 3 weeks")
    }

    @Test("The start date round-trips through a date picker shown in UTC")
    func startDate() throws {
        let form = try form()
        let day = CalendarDay(year: 2027, month: 1, day: 31)
        form.startDate = BudgetDays.date(day)
        #expect(form.startDay == day)
        #expect(form.startDate == BudgetDays.date(day))
    }

    @Test("Currency choices read “INR — Indian Rupee”")
    func currencyTitle() throws {
        let form = try form()
        #expect(form.currencyTitle(for: "INR").hasPrefix("INR — "))
        #expect(form.currencyOptions.contains("INR"))
    }

    // MARK: Saving

    @Test("D307.8: Save makes the budget, one “New Budget Eating out” step, and reloads (#25 AC 6)")
    func saveNew() throws {
        let form = try form()
        fill(form, name: " Eating out ")
        form.carriesOverOverspending = true
        let before = updates.revision
        #expect(form.save() == .saved)
        let budget = try #require(try repository.budgets().first)
        #expect(budget.name == "Eating out")
        #expect(budget.limit(forPeriodStartingOn: budget.startDay) == 8_000)
        #expect(budget.categoryIDs == [B.eatingOutID])
        #expect(budget.carriesOverOverspending && !budget.carriesOverUnspent, "D307.1: independent switches")
        #expect(updates.revision == before + 1)
        #expect(window.history.undoTitle == "New Budget Eating out")
        #expect(!form.hasUnsavedEdits)
        window.history.undo()
        #expect(try repository.budgets().isEmpty)
    }

    @Test("D307.8: saving an edit, a new limit included, is one “Edit Budget” step")
    func saveEdit() throws {
        let budget = B.budget("Eating out", limit: 8_000)
        let setup = try Self.with([budget])
        let form = try setup.form(.edit(budget.id))
        form.name = "Dining"
        form.limitText = "9,500"
        #expect(form.save() == .saved)
        #expect(setup.window.history.undoTitle == "Edit Budget Dining")
        let saved = try #require(try setup.repository.budgets().first)
        #expect(saved.name == "Dining")
        setup.window.history.undo()
        #expect(try setup.repository.budgets().first?.name == "Eating out")
    }

    @Test("D307.7: a new start or repeat for a budget with past periods asks first")
    func recalculation() throws {
        let budget = B.budget("Eating out", limit: 8_000, from: CalendarDay(year: 2026, month: 8, day: 1))
        let setup = try Self.with([budget])
        let form = try setup.form(.edit(budget.id))
        form.repeatChoice = .weekly
        #expect(form.save() == .confirmRecalculation)
        #expect(try setup.repository.budgets().first?.recurrence == .monthly, "Nothing is saved before Save")
        #expect(form.recalculationTitle == "Recalculate Past Periods?")
        #expect(
            form.recalculationMessage
                == "Past periods of “Eating out” are recalculated, so their spent and carry-over can change. Each limit keeps the date it applies from."
        )
        #expect(form.save(confirmed: true) == .saved)
        #expect(try setup.repository.budgets().first?.recurrence == .weekly)
    }

    @Test("D307.7: other edits, or a budget with no past periods, save without asking")
    func noRecalculation() throws {
        let past = B.budget("Eating out", limit: 8_000, from: CalendarDay(year: 2026, month: 8, day: 1))
        let fresh = B.budget("Shopping", limit: 500, categories: [B.shoppingID])
        let setup = try Self.with([past, fresh])
        let rename = try setup.form(.edit(past.id))
        rename.name = "Dining"
        #expect(rename.save() == .saved)
        let repeatChange = try setup.form(.edit(fresh.id))
        repeatChange.repeatChoice = .weekly
        #expect(repeatChange.save() == .saved)
    }

    @Test("Without a window history the save still reloads every screen")
    func noHistory() throws {
        let budgets = DefaultBudgetUseCases(repository: repository, now: { T.now })
        let form = try BudgetFormViewModel(
            mode: .new,
            useCases: BudgetFormUseCases(
                budgets: budgets,
                changes: budgets,
                categories: DefaultCategoryEditingUseCase(repository: repository),
            ),
            today: T.today,
            locale: T.india,
            defaultCurrency: "INR",
            updates: updates,
        )
        fill(form)
        let before = updates.revision
        #expect(form.save() == .saved)
        #expect(updates.revision == before + 1)
    }

    // MARK: Entry point

    @Test("UI Designer's #175 ruling 1: New Budget is offered only with the form and an expense category")
    func canCreate() throws {
        let budgets = DefaultBudgetUseCases(repository: repository, now: { T.now })
        let categories = DefaultCategoryEditingUseCase(repository: repository)
        let withForm = BudgetsFeature(
            useCases: BudgetScreenUseCases(
                list: budgets,
                form: BudgetFormUseCases(budgets: budgets, changes: budgets, categories: categories),
            ),
            locale: T.india,
            today: { T.today },
        )
        #expect(withForm.canCreateBudget())
        #expect(try withForm.makeForm(.new).isNew)
        #expect(!B.feature(repository).canCreateBudget(), "No form use cases, no entry point")
        for category in try categories.listing().categories where category.kind == .expense {
            var archived = category
            archived.isArchived = true
            try repository.saveCategory(archived)
        }
        #expect(!withForm.canCreateBudget(), "Nothing to pick: hidden, never disabled")
    }
}

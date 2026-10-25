import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// What the Mac Budgets screen (#25 part 5) adds to the shared view models: the list's count line, the detail
/// table's separate columns (D239, D240), Today, and the menu and context-menu titles. Today is 20 Oct 2026.
@MainActor
@Suite("Mac Budgets screen (#25)")
struct BudgetMacScreenTests {
    typealias T = TransactionFeatureFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFeatureFixture  // swiftlint:disable:this type_name

    @Test("The list's count line: “1 budget”, then “3 budgets · 1 overspent”; none before the first load")
    func countLine() throws {
        let one = B.feature(try B.repository([B.budget("Eating out", limit: 9_500)])).makeList()
        #expect(one.summaryText == nil)
        one.load()
        #expect(one.summaryText == "1 budget")

        let budgets = [
            B.budget("Eating out", limit: 9_500),
            B.budget("Shopping", limit: 5_000, categories: [B.shoppingID]),
            B.budget("Travel", limit: 60_000, categories: [B.shoppingID]),
        ]
        let several = B.feature(try B.repository(budgets, [B.expense(6_200, in: B.shoppingID)])).makeList()
        several.load()
        #expect(several.summaryText == "3 budgets · 1 overspent")

        let empty = B.feature(try B.repository()).makeList()
        empty.load()
        #expect(empty.summaryText == nil, "The empty state says it instead")
    }

    @Test("D239, D240: the detail table's Category, Account and full Date, with “Split ·” kept in Category")
    func tableColumns() throws {
        let repository = try B.repository()
        let expense = T.expense(1_000, on: T.date(2026, 10, 3), category: B.shoppingID, payee: nil, details: "Mug")
        let split = T.expense(1_240, on: T.date(2026, 10, 12), payee: nil, details: "Green Basket")
        for transaction in [expense, split] {
            try repository.saveTransaction(transaction)
        }
        try repository.replaceSplits(
            [
                TransactionSplit(transactionID: split.id, categoryID: B.eatingOutID, amount: 240),
                TransactionSplit(transactionID: split.id, categoryID: nil, amount: 1_000, sortOrder: 1),
            ],
            for: split.id,
        )
        let budget = B.budget("Shopping", limit: 5_000, categories: [B.shoppingID, B.eatingOutID])
        try repository.saveBudget(budget)
        let model = try #require(BudgetDetailViewModelTests.feature(repository).makeDetail(budget.id))
        model.load()

        let rows = model.transactions
        #expect(rows.map(\.categoryText) == ["Split · Eating out", "Shopping trips"])
        #expect(rows.map(\.accountText) == ["Everyday Savings", "Everyday Savings"])
        #expect(rows.map(\.fullDateText) == ["12 Oct 2026", "3 Oct 2026"])
        #expect(rows[0].subtitle == "Split · Eating out · Everyday Savings", "iOS keeps its one line")
        #expect(model.categoriesLine == "Categories: Eating out and Shopping trips")
    }

    @Test("Today goes back to the current period from a past one")
    func today() throws {
        let budget = B.budget("Eating out", limit: 7_000, from: CalendarDay(year: 2026, month: 8, day: 1))
        let model = try #require(BudgetDetailViewModelTests.feature(try B.repository([budget])).makeDetail(budget.id))
        model.load()
        #expect(!model.canShowCurrentPeriod)
        model.showPreviousPeriod()
        model.showPreviousPeriod()
        #expect(
            model.header?.periodText
                == BudgetDetailViewModelTests.range(
                    CalendarDay(year: 2026, month: 8, day: 1),
                    CalendarDay(year: 2026, month: 8, day: 31),
                )
        )
        #expect(model.canShowCurrentPeriod)
        model.showCurrentPeriod()
        #expect(model.header?.periodText == BudgetDetailViewModelTests.october)
        #expect(model.header?.isCurrentPeriod == true)
        #expect(!model.canShowCurrentPeriod)
    }

    @Test("The Mac's menu and right-click titles, with “…” where they ask for more, as the Mac does")
    func menuTitles() {
        #expect(BudgetText.budgetMenu == "Budget")
        #expect(BudgetText.newBudgetEllipsis == "New Budget…")
        #expect(BudgetText.openBudget == "Open Budget")
        #expect(BudgetText.editBudgetEllipsis == "Edit Budget…")
        #expect(BudgetText.changeBudgetLimitEllipsis == "Change Budget Limit…")
        #expect(BudgetText.duplicate == "Duplicate")
        #expect(BudgetText.showPreviousPeriod == "Show Previous Period")
        #expect(BudgetText.showNextPeriod == "Show Next Period")
        #expect(BudgetText.showCurrentPeriod == "Show Current Period")
        #expect(BudgetText.today == "Today")
        #expect(BudgetText.deleteBudgetEllipsis == "Delete Budget…")
    }

    @Test("The Mac tables' column titles, as the Mac Budgets frames show them")
    func columnTitles() {
        #expect(
            [
                BudgetText.budgetColumn, BudgetText.progressColumn, BudgetText.spentColumn, BudgetText.leftColumn,
                BudgetText.periodColumn,
            ] == ["Budget", "Progress", "Spent", "Left", "Period"]
        )
        #expect(
            [
                BudgetText.dateColumn, BudgetText.payeeColumn, BudgetText.categoryColumn, BudgetText.accountColumn,
                BudgetText.amountColumn,
            ] == ["Date", "Payee", "Category", "Account", "Amount"]
        )
    }

    @Test("The copy's name: “‹Name› copy”, then “‹Name› copy 2”")
    func copyNames() {
        #expect(BudgetText.copyName("Eating out", number: 1) == "Eating out copy")
        #expect(BudgetText.copyName("Eating out", number: 2) == "Eating out copy 2")
    }
}

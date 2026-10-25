import Foundation
import LittleOrbitDomain
import Testing

/// The budget detail's periods and transactions (#25 part 4): the counted line of each transaction, refunds and
/// split lines (D117.10, D237, S72–S75), and moving between periods.
@MainActor
@Suite("Budget detail (#25)")
struct BudgetDetailTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFixture  // swiftlint:disable:this type_name

    private let today = F.day(2026, 11, 20)

    private func refund(_ amount: Decimal, of expense: Transaction?, on date: Date) -> Transaction {
        Transaction(
            type: .income,
            amount: amount,
            date: date,
            timeZoneID: F.india,
            accountID: F.savingsID,
            categoryID: B.shoppingID,
            refundOfID: expense?.id,
            isRefund: true,
            createdAt: date,
        )
    }

    private func useCases(_ snapshot: LedgerSnapshot) -> DefaultBudgetUseCases {
        DefaultBudgetUseCases(repository: FakeBudgetRepository(snapshot), now: { F.date(2026, 11, 5) })
    }

    @Test("S72, D117.10: the expense, its +refund and only the budgeted split line, newest first; spent is 940")
    func refundAndSplitLines() throws {
        let budget = B.budget("Shopping", limit: 5_000, categories: [B.shoppingID, B.householdID])
        let expense = B.expense(1_000, in: B.shoppingID, on: F.date(2026, 11, 3))
        let refund = refund(300, of: expense, on: F.date(2026, 11, 8))
        let split = B.expense(1_240, in: nil, on: F.date(2026, 11, 12))
        var snapshot = try B.saving([expense, refund, split])
        snapshot = try LedgerBook.replacingSplits(
            [
                TransactionSplit(transactionID: split.id, categoryID: B.householdID, amount: 240),
                TransactionSplit(transactionID: split.id, categoryID: B.groceriesID, amount: 1_000, sortOrder: 1),
            ],
            for: split.id,
            in: snapshot,
            now: F.date(2026, 11, 12),
        )
        snapshot = try LedgerBook.savingBudget(budget, in: snapshot, now: F.date(2026, 11, 1))

        let detail = try useCases(snapshot).detail(of: budget.id, period: nil, today: today)
        #expect(detail.selected.figures.spent == 940)
        #expect(detail.lines.map(\.transaction.id) == [split.id, refund.id, expense.id])
        #expect(detail.lines.map(\.amount) == [240, -300, 1_000])
        #expect(detail.lines.map(\.isSplitLine) == [true, false, false])
        #expect(detail.lines[0].categoryID == B.householdID, "Only the Household line, never Groceries (S73)")
        #expect(detail.lines[1].refund == .linked(originalID: expense.id))
    }

    @Test("S74: an orphaned refund is listed as one whose original was deleted, and still lowers spent")
    func orphanedRefund() throws {
        let budget = B.budget("Shopping", limit: 5_000, categories: [B.shoppingID])
        let expense = B.expense(600, in: B.shoppingID, on: F.date(2026, 11, 3))
        var snapshot = try B.saving([expense, refund(120, of: expense, on: F.date(2026, 11, 4))], budgets: [budget])
        snapshot = try LedgerBook.deletingTransaction(id: expense.id, in: snapshot, now: F.date(2026, 11, 5))
        let detail = try useCases(snapshot).detail(of: budget.id, period: nil, today: today)
        #expect(detail.lines.map(\.refund) == [.originalDeleted])
        #expect(detail.selected.figures.netSpending == -120)
    }

    @Test("Only the period's own transactions in the budget's currency and categories are listed")
    func onlyThePeriod() throws {
        let budget = B.budget(categories: [B.foodID], from: F.day(2026, 10, 1))
        let october = B.expense(100, in: B.groceriesID, on: F.date(2026, 10, 20))
        let november = B.expense(200, in: B.restaurantsID, on: F.date(2026, 11, 2))
        let dollars = B.expense(5, in: B.foodID, on: F.date(2026, 11, 3), account: F.usdID)
        let other = B.expense(50, in: B.shoppingID, on: F.date(2026, 11, 3))
        let snapshot = try B.saving([october, november, dollars, other], budgets: [budget])
        let current = try useCases(snapshot).detail(of: budget.id, period: nil, today: today)
        #expect(current.currentIndex == 1)
        #expect(current.selected.period.index == 1)
        #expect(current.lines.map(\.transaction.id) == [november.id])
        #expect(current.selected.excludedCurrencies == ["USD"])
        #expect(
            current.excludedAccounts == [
                BudgetExcludedAccount(accountID: F.usdID, currencyCode: "USD", transactionCount: 1)
            ]
        )

        let past = try useCases(snapshot).detail(of: budget.id, period: 0, today: today)
        #expect(past.selected.period.index == 0)
        #expect(past.lines.map(\.transaction.id) == [october.id])
        #expect(past.currentIndex == 1)
    }

    @Test("D311.1: other-currency transactions in the period are counted once each, by account")
    func excludedAccounts() throws {
        let budget = B.budget(categories: [B.foodID], from: F.day(2026, 10, 1))
        let snapshot = try B.saving(
            [
                B.expense(5, in: B.groceriesID, on: F.date(2026, 11, 3), account: F.usdID),
                B.expense(7, in: B.restaurantsID, on: F.date(2026, 11, 4), account: F.usdID),
                B.expense(900, in: B.foodID, on: F.date(2026, 11, 5), account: F.jpyID),
                B.expense(3, in: B.foodID, on: F.date(2026, 10, 30), account: F.usdID),
                B.expense(4, in: B.shoppingID, on: F.date(2026, 11, 6), account: F.usdID),
            ],
            budgets: [budget],
        )
        let current = try useCases(snapshot).detail(of: budget.id, period: nil, today: today)
        #expect(
            current.excludedAccounts == [
                BudgetExcludedAccount(accountID: F.usdID, currencyCode: "USD", transactionCount: 2),
                BudgetExcludedAccount(accountID: F.jpyID, currencyCode: "JPY", transactionCount: 1),
            ]
        )
        #expect(current.lines.isEmpty)
        let past = try useCases(snapshot).detail(of: budget.id, period: 0, today: today)
        #expect(
            past.excludedAccounts == [
                BudgetExcludedAccount(accountID: F.usdID, currencyCode: "USD", transactionCount: 1)
            ]
        )
    }

    @Test("Periods stop at the current one: a later index shows the current period, a negative one the first")
    func clampsPeriods() throws {
        let budget = B.budget(from: F.day(2026, 10, 1))
        let snapshot = try B.saving([], budgets: [budget])
        #expect(try useCases(snapshot).detail(of: budget.id, period: 7, today: today).selected.period.index == 1)
        #expect(try useCases(snapshot).detail(of: budget.id, period: -1, today: today).selected.period.index == 0)
    }

    @Test("Before the start date the first period shows, not started")
    func beforeStart() throws {
        let budget = B.budget(from: F.day(2026, 12, 1))
        let detail = try useCases(try B.saving([], budgets: [budget])).detail(of: budget.id, period: nil, today: today)
        #expect(detail.currentIndex == 0)
        #expect(detail.selected.state == .notStarted)
        #expect(detail.summary.daysUntilNextPeriod == 11)
    }

    @Test("A deleted budget throws missingBudget")
    func missing() throws {
        #expect(throws: LedgerValidationError.missingBudget) {
            try useCases(B.ledger).detail(of: UUID(), period: nil, today: today)
        }
    }

    @Test("The detail lists the budget's live categories and the accounts and payees to name rows by")
    func lookups() throws {
        let budget = B.budget(categories: [B.foodID])
        let detail = try useCases(try B.saving([], budgets: [budget])).detail(of: budget.id, period: nil, today: today)
        #expect(detail.categories.contains { $0.id == B.groceriesID })
        #expect(detail.accounts.contains { $0.id == F.savingsID })
        #expect(detail.hasNoCategories == false)
    }
}

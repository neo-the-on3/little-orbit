import Foundation
import LittleOrbitDomain
import Testing

/// Budget figures (#25, D217): spent, carry-over, limit history and states.
@Suite("Budget figures (#25)")
struct BudgetProgressTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFixture  // swiftlint:disable:this type_name

    private let november = F.date(2026, 11, 10)
    private let today = F.day(2026, 11, 20)

    private func current(_ budget: Budget, _ transactions: [Transaction]) throws -> BudgetPeriodFigures {
        let snapshot = try B.saving(transactions, budgets: [budget])
        return BudgetProgress.summary(of: budget, today: today, in: snapshot).current
    }

    @Test("S1, S65: two expenses in the budget's category are spent, and remaining is the rest")
    func spentAndRemaining() throws {
        let figures = try current(
            B.budget(),
            [B.expense(1_200, on: november), B.expense(800, on: F.date(2026, 11, 12))],
        )
        #expect(figures.figures.spent == 2_000)
        #expect(figures.figures.remaining == 6_000)
        #expect(figures.limit == 8_000)
        #expect(figures.state == .onTrack)
        #expect(figures.period.start == F.day(2026, 11, 1))
        #expect(figures.period.end == F.day(2026, 11, 30))
    }

    @Test("S9, S10, D217.1: a parent covers its subcategories, including one added later")
    func parentCoversSubcategories() throws {
        var snapshot = try B.saving([], budgets: [])
        let snacks = TransactionCategory(name: "Snacks", kind: .expense, parentID: B.foodID, sortOrder: 2)
        snapshot = try LedgerBook.savingCategory(snacks, in: snapshot, now: november)
        let budget = B.budget(categories: [B.foodID])
        snapshot = try B.saving(
            [
                B.expense(300, in: B.groceriesID, on: november),
                B.expense(200, in: snacks.id, on: november),
                B.expense(100, in: B.foodID, on: november),
            ],
            budgets: [budget],
            in: snapshot,
        )
        #expect(BudgetProgress.summary(of: budget, today: today, in: snapshot).current.figures.spent == 600)
    }

    @Test("S11, S13: a subcategory budget skips its siblings, and uncategorised counts nowhere")
    func subcategoryOnly() throws {
        let figures = try current(
            B.budget(categories: [B.groceriesID]),
            [B.expense(500, in: B.restaurantsID, on: november), B.expense(70, in: nil, on: november)],
        )
        #expect(figures.figures.spent == 0)
    }

    @Test("D217.3: picking a parent and its subcategory counts each expense once")
    func noDoubleCounting() throws {
        let figures = try current(
            B.budget(categories: [B.foodID, B.groceriesID]),
            [B.expense(400, in: B.groceriesID, on: november)],
        )
        #expect(figures.figures.spent == 400)
    }

    @Test("D217.4: a subcategory with its own budget still counts in the parent's")
    func budgetsIndependent() throws {
        let parent = B.budget("Food", categories: [B.foodID])
        let child = B.budget("Groceries", categories: [B.groceriesID])
        let snapshot = try B.saving([B.expense(400, in: B.groceriesID, on: november)], budgets: [parent, child])
        #expect(BudgetProgress.summary(of: parent, today: today, in: snapshot).current.figures.spent == 400)
        #expect(BudgetProgress.summary(of: child, today: today, in: snapshot).current.figures.spent == 400)
    }

    @Test("D217.2: a split expense counts only its line in the budget's category")
    func splitLines() throws {
        let expense = B.expense(1_000, in: nil, on: november)
        var snapshot = try B.saving([expense])
        snapshot = try LedgerBook.replacingSplits(
            [
                TransactionSplit(transactionID: expense.id, categoryID: B.restaurantsID, amount: 240),
                TransactionSplit(transactionID: expense.id, categoryID: B.householdID, amount: 760, sortOrder: 1),
            ],
            for: expense.id,
            in: snapshot,
            now: november,
        )
        let budget = B.budget()
        snapshot = try LedgerBook.savingBudget(budget, in: snapshot, now: november)
        #expect(BudgetProgress.summary(of: budget, today: today, in: snapshot).current.figures.spent == 240)
    }

    @Test("S44, S45, D217.5: a linked refund lowers spent, and still does once its expense is deleted")
    func refunds() throws {
        let budget = B.budget("Shopping", limit: 5_000, categories: [B.shoppingID])
        let expense = B.expense(2_000, in: B.shoppingID, on: november)
        let refund = Transaction(
            type: .income,
            amount: 500,
            date: F.date(2026, 11, 12),
            timeZoneID: F.india,
            accountID: F.savingsID,
            categoryID: B.shoppingID,
            refundOfID: expense.id,
            isRefund: true,
            createdAt: F.date(2026, 11, 12),
        )
        var snapshot = try B.saving([expense, refund], budgets: [budget])
        #expect(BudgetProgress.summary(of: budget, today: today, in: snapshot).current.figures.spent == 1_500)
        snapshot = try LedgerBook.deletingTransaction(id: expense.id, in: snapshot, now: november)
        let after = BudgetProgress.summary(of: budget, today: today, in: snapshot).current.figures
        #expect(after.netSpending == -500)
        #expect(after.spent == 0)
        #expect(after.credit == 500)
        #expect(after.remaining == 5_500)
    }

    @Test("S12, S66: transfers and income never count, even in a same-named income category")
    func transfersAndIncome() throws {
        let income = Transaction(
            type: .income,
            amount: 900,
            date: november,
            timeZoneID: F.india,
            accountID: F.savingsID,
            categoryID: B.shoppingIncomeID,
            createdAt: november,
        )
        let figures = try current(
            B.budget("Shopping", categories: [B.shoppingID]),
            [income, F.transfer(300, on: november)],
        )
        #expect(figures.figures.netSpending == 0)
    }

    @Test("S5, S6, S7, D17: only the budget's currency counts, and the other currencies are listed")
    func oneCurrency() throws {
        let rupees = B.expense(500, in: B.foodID, on: november)
        let dollars = B.expense(20, in: B.foodID, on: november, account: F.usdID)
        let inr = try current(B.budget(categories: [B.foodID]), [rupees, dollars])
        #expect(inr.figures.spent == 500)
        #expect(inr.excludedCurrencies == ["USD"])
        let usd = try current(B.budget(limit: 100, categories: [B.foodID], currency: "USD"), [rupees, dollars])
        #expect(usd.figures.spent == 20)
        #expect(usd.excludedCurrencies == ["INR"])
        let none = try current(B.budget(categories: [B.foodID]), [dollars])
        #expect(none.figures.spent == 0)
    }

    @Test("S28: a future-dated expense counts in its own period, not the current one")
    func futureDated() throws {
        let budget = B.budget()
        let snapshot = try B.saving([B.expense(700, on: F.date(2026, 12, 5))], budgets: [budget])
        #expect(BudgetProgress.figures(of: budget, period: 0, in: snapshot).figures.spent == 0)
        #expect(BudgetProgress.figures(of: budget, period: 1, in: snapshot).figures.spent == 700)
    }

    @Test("S25, S63: a transaction counts on its own calendar day, whatever the device's zone")
    func ownDay() throws {
        let budget = B.budget(from: F.day(2027, 1, 31))
        let late = B.expense(100, on: F.date(2027, 2, 27, 23, 59))
        let early = B.expense(200, on: F.date(2027, 2, 28, 0, 1))
        let snapshot = try B.saving([late, early], budgets: [budget])
        #expect(BudgetProgress.figures(of: budget, period: 0, in: snapshot).figures.spent == 100)
        #expect(BudgetProgress.figures(of: budget, period: 1, in: snapshot).figures.spent == 200)
    }

    @Test("S2: carry-over adds 1,500 unused to a 5,000 limit")
    func carryUnused() throws {
        let budget = B.budget(limit: 5_000, unspent: true)
        let snapshot = try B.saving([B.expense(3_500, on: november)], budgets: [budget])
        let next = BudgetProgress.figures(of: budget, period: 1, in: snapshot)
        #expect(next.figures.carriedOver == 1_500)
        #expect(next.figures.available == 6_500)
        #expect(BudgetProgress.figures(of: budget, period: 0, in: snapshot).carriedForward == 1_500)
    }

    @Test("S3: 700 overspent carries only with carry over overspending on")
    func carryOverspending() throws {
        let over = [B.expense(5_700, on: november)]
        let carried = B.budget(limit: 5_000, unspent: true, overspending: true)
        let off = B.budget("Groceries run", limit: 5_000, unspent: true)
        let snapshot = try B.saving(over, budgets: [carried, off])
        #expect(BudgetProgress.figures(of: carried, period: 1, in: snapshot).figures.available == 4_300)
        #expect(BudgetProgress.figures(of: off, period: 1, in: snapshot).figures.available == 5_000)
    }

    @Test("Without carry over unspent, unused money doesn't carry")
    func noCarry() throws {
        let budget = B.budget(limit: 5_000, overspending: true)
        let snapshot = try B.saving([B.expense(1_000, on: november)], budgets: [budget])
        #expect(BudgetProgress.figures(of: budget, period: 1, in: snapshot).figures.available == 5_000)
    }

    @Test("S62: 8,000 with +1,000 carried gives 9,000, then 500 over gives 7,500, with no pro-rating")
    func carryChain() throws {
        let budget = B.budget(from: F.day(2027, 1, 31), unspent: true, overspending: true)
        let snapshot = try B.saving(
            [B.expense(7_000, on: F.date(2027, 2, 10)), B.expense(9_500, on: F.date(2027, 3, 10))],
            budgets: [budget],
        )
        #expect(BudgetProgress.figures(of: budget, period: 1, in: snapshot).figures.available == 9_000)
        #expect(BudgetProgress.figures(of: budget, period: 2, in: snapshot).figures.available == 7_500)
    }

    @Test("S27, S51: a limit change applies from its period; earlier periods and their carry-over keep the old limit")
    func limitHistory() throws {
        var budget = B.budget(limit: 8_000, unspent: true)
        let snapshot0 = try B.saving([B.expense(5_500, on: november)], budgets: [budget])
        let changed = try LedgerBook.changingBudgetLimit(
            of: budget.id,
            to: 10_000,
            fromPeriodStartingOn: F.day(2026, 12, 1),
            in: snapshot0,
            now: november,
        )
        budget = try #require(changed.budgets.first)
        let first = BudgetProgress.figures(of: budget, period: 0, in: changed)
        #expect(first.limit == 8_000)
        #expect(first.carriedForward == 2_500)
        let second = BudgetProgress.figures(of: budget, period: 1, in: changed)
        #expect(second.limit == 10_000)
        #expect(second.figures.available == 12_500)
    }

    @Test("S21, S22, S69: exactly at the limit isn't overspent, one paisa over is, and 90% is near the limit")
    func states() throws {
        #expect(try current(B.budget(), [B.expense(8_000, on: november)]).state == .nearLimit)
        #expect(try current(B.budget(), [B.expense(Decimal(string: "8000.01")!, on: november)]).state == .overspent)
        #expect(try current(B.budget(), [B.expense(7_200, on: november)]).state == .nearLimit)
        #expect(try current(B.budget(), [B.expense(Decimal(string: "7199.99")!, on: november)]).state == .onTrack)
        #expect(try current(B.budget(), []).state == .onTrack)
    }

    @Test("S20: tiny and huge limits stay exact")
    func exactAmounts() throws {
        let tiny = try current(B.budget(limit: Decimal(string: "0.01")!), [])
        #expect(tiny.figures.remaining == Decimal(string: "0.01")!)
        let huge = try current(
            B.budget(limit: Decimal(string: "999999999.99")!),
            [B.expense(Decimal(string: "0.01")!, on: november)],
        )
        #expect(huge.figures.remaining == Decimal(string: "999999999.98")!)
    }

    @Test("A budget that hasn't started shows its first period as not started, and counts days to its start")
    func notStarted() throws {
        let budget = B.budget(from: F.day(2026, 12, 1))
        let snapshot = try B.saving([], budgets: [budget])
        let summary = BudgetProgress.summary(of: budget, today: today, in: snapshot)
        #expect(summary.current.state == .notStarted)
        #expect(summary.current.period.start == F.day(2026, 12, 1))
        #expect(summary.daysUntilNextPeriod == 11)
        #expect(!summary.isOverspent)
    }

    @Test("D217.7: an archived subcategory still counts in its parent's budget")
    func archivedSubcategory() throws {
        let budget = B.budget(categories: [B.foodID])
        var snapshot = try B.saving([B.expense(250, in: B.groceriesID, on: november)], budgets: [budget])
        snapshot = try LedgerBook.archivingCategory(id: B.groceriesID, archived: true, in: snapshot, now: november)
        #expect(BudgetProgress.summary(of: budget, today: today, in: snapshot).current.figures.spent == 250)
    }

    @Test("D217.6: a subcategory moved to another parent counts there for every period")
    func movedSubcategory() throws {
        let food = B.budget("Food", categories: [B.foodID])
        let shopping = B.budget("Shopping", categories: [B.shoppingID])
        var snapshot = try B.saving([B.expense(250, in: B.groceriesID, on: november)], budgets: [food, shopping])
        var groceries = try #require(snapshot.categories.first { $0.id == B.groceriesID })
        groceries.parentID = B.shoppingID
        snapshot = try LedgerBook.savingCategory(groceries, in: snapshot, now: november)
        #expect(BudgetProgress.summary(of: food, today: today, in: snapshot).current.figures.spent == 0)
        #expect(BudgetProgress.summary(of: shopping, today: today, in: snapshot).current.figures.spent == 250)
    }
}

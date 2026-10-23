import Foundation
import LittleOrbitDomain
import Testing

/// Report and budget totals per category with splits and refunds (#34 acceptance criterion: "Given fixture
/// data includes splits and refunds When reports and budgets are generated Then totals per category match the
/// fixture"). Uses fixture F34; all names and amounts are made up.
@Suite("Category spending with splits and refunds")
struct CategorySpendingTests {
    private let october = (CalendarDay(year: 2026, month: 10, day: 1), CalendarDay(year: 2026, month: 10, day: 31))
    private let november = (CalendarDay(year: 2026, month: 11, day: 1), CalendarDay(year: 2026, month: 11, day: 30))

    private func inr(_ category: TransactionCategory) -> CategoryCurrency {
        CategoryCurrency(categoryID: category.id, currencyCode: "INR")
    }

    /// October and November of F34: splits, linked and orphaned refunds, a fully refunded expense, income, a
    /// transfer, a USD expense, and a refund dated in the month after its expense.
    private func fixture() throws -> SplitsRefundsFixture {
        typealias F = SplitsRefundsFixture  // swiftlint:disable:this type_name
        var fixture = try SplitsRefundsFixture()
        let trailhead = try fixture.expense(1_000, in: fixture.shopping, on: F.date(10, 17))
        try fixture.refund(300, of: trailhead, in: fixture.shopping, on: F.date(10, 20))
        try fixture.split(
            [(fixture.groceries, 900), (fixture.household, 240), (fixture.drinks, 100)],
            on: F.date(10, 20),
        )
        try fixture.split([(fixture.groceries, 40), (fixture.household, 50)], on: F.date(10, 21))
        let medicine = try fixture.expense(500, in: fixture.pharmacy, on: F.date(10, 5))
        try fixture.refund(500, of: medicine, in: fixture.pharmacy, on: F.date(10, 6))
        try fixture.refund(150, of: nil, in: fixture.pharmacy, on: F.date(10, 9))
        let lateRefunded = try fixture.expense(200, in: fixture.groceries, on: F.date(10, 28))
        try fixture.refund(50, of: lateRefunded, in: fixture.groceries, on: F.date(11, 3), account: fixture.wallet)
        try fixture.income(50_000, in: fixture.salary, on: F.date(10, 1))
        try fixture.transfer(2_000, on: F.date(10, 2))
        try fixture.expense(12, in: fixture.shopping, on: F.date(10, 11), account: fixture.travel)
        return fixture
    }

    @Test("Report totals per category match the fixture: each split line in its own category, refunds lower it")
    func reportTotals() throws {
        let fixture = try fixture()
        let spending = CategorySpending.spending(in: fixture.snapshot, from: october.0, through: october.1)
        #expect(spending[inr(fixture.shopping)] == 700)
        #expect(spending[inr(fixture.groceries)] == 1_140)
        #expect(spending[inr(fixture.household)] == 290)
        #expect(spending[inr(fixture.drinks)] == 100)
        #expect(spending[inr(fixture.pharmacy)] == -150)
        #expect(spending[CategoryCurrency(categoryID: fixture.shopping.id, currencyCode: "USD")] == 12)
        #expect(spending.count == 6)
    }

    @Test("Refunds aren't income; salary is (#55, S20, S23)")
    func incomeLeavesRefundsOut() throws {
        let fixture = try fixture()
        let income = CategorySpending.income(in: fixture.snapshot, from: october.0, through: october.1)
        #expect(income == [inr(fixture.salary): 50_000])
    }

    @Test("A refund counts in the period it's dated, not its expense's (D33.3, S17 with no Counts on date)")
    func refundCountsOnItsOwnDate() throws {
        let fixture = try fixture()
        let spending = CategorySpending.spending(in: fixture.snapshot, from: november.0, through: november.1)
        #expect(spending == [inr(fixture.groceries): -50])
    }

    @Test("Budget spent per category matches the report total for that category")
    func budgetsMatchReports() throws {
        let fixture = try fixture()
        let report = CategorySpending.spending(in: fixture.snapshot, from: october.0, through: october.1)
        for category in [fixture.shopping, fixture.groceries, fixture.household, fixture.drinks, fixture.pharmacy] {
            let spent = CategorySpending.spent(
                on: [category.id],
                currencyCode: "INR",
                in: fixture.snapshot,
                from: october.0,
                through: october.1,
            )
            #expect(spent == report[inr(category)], "\(category.name)")
        }
    }

    @Test("A Shopping budget that also selects Household spends ₹940.00: 1,000 − 300 + 240 (D117.10, S64)")
    func budgetDetailExample() throws {
        typealias F = SplitsRefundsFixture  // swiftlint:disable:this type_name
        var fixture = try SplitsRefundsFixture()
        let trailhead = try fixture.expense(1_000, in: fixture.shopping, on: F.date(10, 17))
        try fixture.refund(300, of: trailhead, in: fixture.shopping, on: F.date(10, 20))
        try fixture.split(
            [(fixture.groceries, 900), (fixture.household, 240), (fixture.drinks, 100)],
            on: F.date(10, 20),
        )
        let spent = CategorySpending.spent(
            on: [fixture.shopping.id, fixture.household.id],
            currencyCode: "INR",
            in: fixture.snapshot,
            from: october.0,
            through: october.1,
        )
        #expect(spent == 940)
    }

    @Test("A fully refunded expense nets its category to 0 (S23)")
    func fullyRefunded() throws {
        typealias F = SplitsRefundsFixture  // swiftlint:disable:this type_name
        var fixture = try SplitsRefundsFixture()
        let expense = try fixture.expense(1_000, in: fixture.shopping, on: F.date(10, 10))
        try fixture.refund(1_000, of: expense, in: fixture.shopping, on: F.date(10, 12))
        let spending = CategorySpending.spending(in: fixture.snapshot, from: october.0, through: october.1)
        #expect(spending[inr(fixture.shopping)] == 0)
    }
}

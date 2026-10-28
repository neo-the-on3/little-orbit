import Foundation
import LittleOrbitDomain
import Testing

/// Made-up data for the spending report tests. Dates are in Asia/Calcutta unless a test says otherwise.
enum ReportFixture {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    static let food = TransactionCategory(name: "Food & Dining", sortOrder: 0)
    static let groceries = TransactionCategory(name: "Groceries", parentID: food.id, sortOrder: 1)
    static let restaurants = TransactionCategory(name: "Restaurants", parentID: food.id, sortOrder: 2)
    static let rent = TransactionCategory(name: "Rent", sortOrder: 3)
    static let electronics = TransactionCategory(name: "Electronics", sortOrder: 4)
    static let household = TransactionCategory(name: "Household", sortOrder: 5)
    static let salary = TransactionCategory(name: "Salary", kind: .income, sortOrder: 6)
    static let categories = [food, groceries, restaurants, rent, electronics, household, salary]

    /// 25 Oct 2026, as in the brief.
    static let today = F.day(2026, 10, 25)

    static func expense(
        _ amount: Decimal,
        _ category: TransactionCategory?,
        on date: Date,
        account: UUID = F.savingsID,
        zone: String = F.india,
    ) -> Transaction {
        var transaction = F.expense(amount, on: date, account: account, zone: zone)
        transaction.categoryID = category?.id
        return transaction
    }

    static func refund(_ amount: Decimal, _ category: TransactionCategory?, on date: Date) -> Transaction {
        var transaction = F.income(amount, on: date)
        transaction.categoryID = category?.id
        transaction.isRefund = true
        return transaction
    }

    static func snapshot(_ transactions: [Transaction], splits: [TransactionSplit] = []) -> LedgerSnapshot {
        LedgerSnapshot(accounts: F.accounts, transactions: transactions, categories: categories, splits: splits)
    }

    static func report(
        _ transactions: [Transaction],
        splits: [TransactionSplit] = [],
        period: ReportPeriod = .thisMonth,
        today: CalendarDay = today,
        currency: String? = nil,
    ) -> SpendingReport {
        SpendingReportBuilder.report(
            in: snapshot(transactions, splits: splits),
            period: period,
            today: today,
            currencyCode: currency,
            defaultCurrency: "INR",
        )
    }
}

@Suite("Spending report periods (#27 core, D316)")
struct ReportPeriodTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    @Test("This Month, Last Month, This Year and Last Year, both ends included")
    func presets() {
        let today = F.day(2026, 10, 25)
        #expect(
            ReportPeriod.thisMonth.range(today: today) == .init(start: F.day(2026, 10, 1), end: F.day(2026, 10, 31))
        )
        #expect(
            ReportPeriod.lastMonth.range(today: today) == .init(start: F.day(2026, 9, 1), end: F.day(2026, 9, 30))
        )
        #expect(
            ReportPeriod.thisYear.range(today: today) == .init(start: F.day(2026, 1, 1), end: F.day(2026, 12, 31))
        )
        #expect(
            ReportPeriod.lastYear.range(today: today) == .init(start: F.day(2025, 1, 1), end: F.day(2025, 12, 31))
        )
    }

    @Test("Last Month in January is December of the year before")
    func januaryEdge() {
        let range = ReportPeriod.lastMonth.range(today: F.day(2027, 1, 1))
        #expect(range == .init(start: F.day(2026, 12, 1), end: F.day(2026, 12, 31)))
    }

    @Test("February has 29 days in a leap year and 28 otherwise; 2100 isn't a leap year, 2000 was")
    func february() {
        #expect(ReportPeriod.thisMonth.range(today: F.day(2028, 2, 10)).end == F.day(2028, 2, 29))
        #expect(ReportPeriod.thisMonth.range(today: F.day(2027, 2, 10)).end == F.day(2027, 2, 28))
        #expect(ReportPeriod.lastMonth.range(today: F.day(2100, 3, 1)).end == F.day(2100, 2, 28))
        #expect(ReportPeriod.lastMonth.range(today: F.day(2000, 3, 1)).end == F.day(2000, 2, 29))
    }

    @Test("The presets are months, quarters and years, in that order (#184)")
    func offeredPresets() {
        #expect(ReportPeriod.allCases == [.thisMonth, .lastMonth, .thisQuarter, .lastQuarter, .thisYear, .lastYear])
    }
}

@Suite("Spending by category (#27 core)")
struct SpendingReportTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = ReportFixture  // swiftlint:disable:this type_name

    @Test("QA fixture: Groceries ₹12,450.50, Rent ₹45,000.00, Dining ₹3,200.00 total ₹60,650.50; no income or transfer")
    func qaFixture() {
        let dining = R.restaurants
        let report = R.report([
            R.expense(12_450.50, R.groceries, on: F.date(2026, 10, 3)),
            R.expense(45_000, R.rent, on: F.date(2026, 10, 1)),
            R.expense(3_200, dining, on: F.date(2026, 10, 8)),
            F.income(150_000, on: F.date(2026, 10, 1)),
            F.transfer(20_000, on: F.date(2026, 10, 5)),
        ])
        #expect(report.rows.map(\.categoryID) == [R.rent.id, R.groceries.id, dining.id])
        #expect(report.rows.map(\.amount) == [45_000, Decimal(string: "12450.50")!, 3_200])
        #expect(report.total == Decimal(string: "60650.50")!)
        #expect(report.currencyCode == "INR")
        #expect(report.currencies == ["INR"])
    }

    @Test("Refunds lower their category: 1,000 Electronics and a 300 refund is 700 (D19)")
    func refundsReduce() {
        let report = R.report([
            R.expense(1_000, R.electronics, on: F.date(2026, 10, 2)),
            R.refund(300, R.electronics, on: F.date(2026, 10, 4)),
        ])
        #expect(report.rows.count == 1)
        #expect(report.rows[0].amount == 700)
        #expect(report.rows[0].transactionCount == 2)
        #expect(report.total == 700)
    }

    @Test("A refund-only category is −300, sorts below 0 and still lowers the total")
    func negativeRow() {
        let report = R.report([
            R.expense(25_000, R.rent, on: F.date(2026, 10, 1)),
            R.refund(300, R.electronics, on: F.date(2026, 10, 4)),
            R.expense(500, R.household, on: F.date(2026, 10, 6)),
        ])
        #expect(report.rows.map(\.categoryID) == [R.rent.id, R.household.id, R.electronics.id])
        #expect(report.rows.last?.amount == -300)
        #expect(report.total == 25_200)
        #expect(report.rows.compactMap(\.shareTenths).reduce(0, +) == 1000)
        #expect(report.rows.last.flatMap(\.shareTenths).map { $0 < 0 } == true)
    }

    @Test("Transfers never count, in or out, and plain income doesn't either")
    func transfersNeverCount() {
        let report = R.report([
            F.transfer(20_000, on: F.date(2026, 10, 5)),
            F.transfer(5_000, on: F.date(2026, 10, 6), from: F.walletID, to: F.savingsID),
            F.income(1_000, on: F.date(2026, 10, 7)),
        ])
        #expect(report.isEmpty)
        #expect(report.total == 0)
    }

    @Test("Expenses with no category are one Uncategorised row")
    func uncategorised() {
        let report = R.report([
            R.expense(1_200, nil, on: F.date(2026, 10, 2)),
            R.expense(800, nil, on: F.date(2026, 10, 3)),
            R.expense(1_500, R.rent, on: F.date(2026, 10, 3)),
        ])
        #expect(report.rows.count == 2)
        let uncategorised = report.rows.first { $0.categoryID == nil }
        #expect(uncategorised?.amount == 2_000)
        #expect(uncategorised?.transactionCount == 2)
        #expect(uncategorised?.category == nil)
    }

    @Test("A deleted category's transactions count as Uncategorised")
    func deletedCategory() {
        var snapshot = R.snapshot([R.expense(400, R.household, on: F.date(2026, 10, 2))])
        snapshot.categories = snapshot.categories.map { category in
            var copy = category
            if copy.id == R.household.id {
                copy.deletedAt = F.date(2026, 10, 3)
            }
            return copy
        }
        let report = SpendingReportBuilder.report(
            in: snapshot,
            period: .thisMonth,
            today: R.today,
            currencyCode: nil,
            defaultCurrency: "INR",
        )
        #expect(report.rows.map(\.categoryID) == [nil])
    }

    @Test("S51/D289: no roll-up; each subcategory is its own row and the parent counts only its own")
    func noRollUp() {
        let report = R.report([
            R.expense(500, R.food, on: F.date(2026, 10, 2)),
            R.expense(2_000, R.groceries, on: F.date(2026, 10, 3)),
            R.expense(1_200, R.restaurants, on: F.date(2026, 10, 4)),
            R.expense(25_000, R.rent, on: F.date(2026, 10, 1)),
        ])
        #expect(report.rows.map(\.categoryID) == [R.rent.id, R.groceries.id, R.restaurants.id, R.food.id])
        #expect(report.rows.map(\.amount) == [25_000, 2_000, 1_200, 500])
        #expect(report.total == 28_700)
        #expect(report.rows.first { $0.categoryID == R.food.id }?.transactionCount == 1)
        #expect(report.rows.first { $0.categoryID == R.groceries.id }?.parent == R.food)
        #expect(report.rows.first { $0.categoryID == R.food.id }?.parent == nil)
        #expect(report.rows.compactMap(\.shareTenths).reduce(0, +) == 1000)
    }

    @Test("A split expense adds each line to its own category, never the whole amount to one row")
    func splits() {
        let expense = R.expense(1_500, R.groceries, on: F.date(2026, 10, 9))
        let lines = [
            TransactionSplit(transactionID: expense.id, categoryID: R.groceries.id, amount: 1_000),
            TransactionSplit(transactionID: expense.id, categoryID: R.household.id, amount: 500),
        ]
        let report = R.report([expense], splits: lines)
        #expect(report.rows.map(\.amount) == [1_000, 500])
        #expect(report.rows.map(\.categoryID) == [R.groceries.id, R.household.id])
        #expect(report.total == 1_500)
    }

    @Test("Deleted transactions and transactions in deleted accounts don't count")
    func deletedRecords() {
        var deleted = R.expense(100, R.rent, on: F.date(2026, 10, 2))
        deleted.deletedAt = F.date(2026, 10, 3)
        var snapshot = R.snapshot([deleted, R.expense(200, R.rent, on: F.date(2026, 10, 2), account: F.walletID)])
        snapshot.accounts = snapshot.accounts.map { account in
            var copy = account
            if copy.id == F.walletID {
                copy.deletedAt = F.date(2026, 10, 4)
            }
            return copy
        }
        let report = SpendingReportBuilder.report(
            in: snapshot,
            period: .thisMonth,
            today: R.today,
            currencyCode: nil,
            defaultCurrency: "INR",
        )
        #expect(report.isEmpty)
    }

    @Test("S20: 31 Oct 23:30 IST is October and 1 Nov 00:15 IST is November, whatever the device zone")
    func monthEdgeInOwnZone() {
        let transactions = [
            R.expense(100, R.rent, on: F.date(2026, 10, 31, 23, 30)),
            R.expense(200, R.rent, on: F.date(2026, 11, 1, 0, 15)),
        ]
        let october = R.report(transactions, today: F.day(2026, 10, 31))
        #expect(october.total == 100)
        let lastMonth = R.report(transactions, period: .lastMonth, today: F.day(2026, 11, 20))
        #expect(lastMonth.total == 100)
        let november = R.report(transactions, today: F.day(2026, 11, 20))
        #expect(november.total == 200)
    }

    @Test("A New York expense on 31 Dec 22:00 is 2026 even though it's 1 Jan in India")
    func yearEdgeInOwnZone() {
        let newYork = "America/New_York"
        let transactions = [
            R.expense(70, R.rent, on: F.date(2026, 12, 31, 22, zone: newYork), zone: newYork),
            R.expense(30, R.rent, on: F.date(2027, 1, 1, 0, 30)),
        ]
        let lastYear = R.report(transactions, period: .lastYear, today: F.day(2027, 1, 2))
        #expect(lastYear.total == 70)
        let thisYear = R.report(transactions, period: .thisYear, today: F.day(2027, 1, 2))
        #expect(thisYear.total == 30)
    }

    @Test("D319.2: a future-dated item counts in the period its date falls in, as budgets count it (S28)")
    func futureDated() {
        let transactions = [
            R.expense(100, R.rent, on: F.date(2026, 10, 25)),
            R.expense(900, R.rent, on: F.date(2026, 10, 26)),
            R.expense(50, R.rent, on: F.date(2026, 11, 2)),
        ]
        let report = R.report(transactions)
        #expect(report.total == 1_000)
        #expect(report.range.end == F.day(2026, 10, 31))
        let entries = SpendingReportBuilder.entries(
            in: R.snapshot(transactions),
            period: .thisMonth,
            today: R.today,
            currencyCode: "INR",
            categoryID: R.rent.id,
        )
        #expect(entries.map(\.amount) == [900, 100])
        #expect(R.report(transactions, period: .thisYear).total == 1_050)
    }

    @Test("Currencies are never added: default first, one at a time, and the picked one is kept")
    func multiCurrency() {
        let transactions = [
            R.expense(1_000, R.rent, on: F.date(2026, 10, 2)),
            R.expense(80, R.groceries, on: F.date(2026, 10, 3), account: F.usdID),
            R.expense(45.50, R.restaurants, on: F.date(2026, 10, 4), account: F.usdID),
            R.expense(1_200, R.groceries, on: F.date(2026, 10, 4), account: F.jpyID),
        ]
        let inr = R.report(transactions)
        #expect(inr.currencies == ["INR", "JPY", "USD"])
        #expect(inr.currencyCode == "INR")
        #expect(inr.total == 1_000)
        let usd = R.report(transactions, currency: "usd")
        #expect(usd.currencyCode == "USD")
        #expect(usd.total == Decimal(string: "125.50")!)
        #expect(usd.rows.map(\.categoryID) == [R.groceries.id, R.restaurants.id])
    }

    @Test("A picked currency with no spending this period falls back to the first one")
    func currencyFallback() {
        let report = R.report(
            [R.expense(80, R.groceries, on: F.date(2026, 10, 3), account: F.usdID)],
            currency: "EUR",
        )
        #expect(report.currencyCode == "USD")
        let empty = R.report([], currency: "EUR")
        #expect(empty.currencyCode == "EUR")
        #expect(empty.currencies.isEmpty)
        #expect(R.report([]).currencyCode == "INR")
    }

    @Test("Totals are exact to the paisa: a thousand ₹0.01 expenses are ₹10.00, and 0.1 + 0.2 is 0.3")
    func paisaExact() {
        var transactions = (0..<1_000)
            .map { _ in R.expense(Decimal(string: "0.01")!, R.rent, on: F.date(2026, 10, 2)) }
        transactions.append(R.expense(Decimal(string: "0.1")!, R.household, on: F.date(2026, 10, 2)))
        transactions.append(R.expense(Decimal(string: "0.2")!, R.household, on: F.date(2026, 10, 3)))
        let report = R.report(transactions)
        #expect(report.rows.first { $0.categoryID == R.rent.id }?.amount == Decimal(string: "10.00")!)
        #expect(report.rows.first { $0.categoryID == R.household.id }?.amount == Decimal(string: "0.3")!)
        #expect(report.total == Decimal(string: "10.3")!)
    }

    @Test("A very large amount stays exact: ₹99,99,99,999.99 plus ₹0.01")
    func largeExact() {
        let report = R.report([
            R.expense(Decimal(string: "999999999.99")!, R.rent, on: F.date(2026, 10, 2)),
            R.expense(Decimal(string: "0.01")!, R.rent, on: F.date(2026, 10, 2)),
        ])
        #expect(report.total == Decimal(string: "1000000000.00")!)
    }

    @Test("The total equals the sum of every row, and each row equals the sum of its drill-down")
    func totalsMatchTransactions() {
        let split = R.expense(Decimal(string: "1500.75")!, nil, on: F.date(2026, 10, 9))
        let transactions = [
            R.expense(Decimal(string: "12450.50")!, R.groceries, on: F.date(2026, 10, 3)),
            R.expense(Decimal(string: "0.33")!, R.groceries, on: F.date(2026, 10, 4)),
            R.refund(Decimal(string: "99.99")!, R.groceries, on: F.date(2026, 10, 5)),
            R.expense(45_000, R.rent, on: F.date(2026, 10, 1)),
            R.expense(Decimal(string: "17.17")!, nil, on: F.date(2026, 10, 2)),
            R.refund(300, R.electronics, on: F.date(2026, 10, 6)),
            split,
            F.transfer(20_000, on: F.date(2026, 10, 5)),
        ]
        let lines = [
            TransactionSplit(transactionID: split.id, categoryID: R.groceries.id, amount: Decimal(string: "1000.25")!),
            TransactionSplit(transactionID: split.id, categoryID: R.household.id, amount: Decimal(string: "500.50")!),
        ]
        let snapshot = R.snapshot(transactions, splits: lines)
        let report = SpendingReportBuilder.report(
            in: snapshot,
            period: .thisMonth,
            today: R.today,
            currencyCode: nil,
            defaultCurrency: "INR",
        )
        #expect(report.total == report.rows.reduce(Decimal(0)) { $0 + $1.amount })
        #expect(report.total == Decimal(string: "58568.76")!)
        for row in report.rows {
            let entries = SpendingReportBuilder.entries(
                in: snapshot,
                period: .thisMonth,
                today: R.today,
                currencyCode: "INR",
                categoryID: row.categoryID,
            )
            #expect(entries.reduce(Decimal(0)) { $0 + $1.amount } == row.amount)
            #expect(entries.count == row.transactionCount)
        }
        #expect(report.rows.first { $0.categoryID == R.groceries.id }?.amount == Decimal(string: "13351.09")!)
    }

    @Test("Equal amounts sort by name, with Uncategorised after named categories")
    func tieOrder() {
        let report = R.report([
            R.expense(100, nil, on: F.date(2026, 10, 2)),
            R.expense(100, R.rent, on: F.date(2026, 10, 2)),
            R.expense(100, R.electronics, on: F.date(2026, 10, 2)),
        ])
        #expect(report.rows.map(\.categoryID) == [R.electronics.id, R.rent.id, nil])
    }

    @Test("The drill-down lists only that row's transactions, newest first, with refunds as negative")
    func drillDown() {
        let older = R.expense(2_000, R.groceries, on: F.date(2026, 10, 3))
        let newer = R.expense(1_240, R.groceries, on: F.date(2026, 10, 20))
        let refund = R.refund(100, R.groceries, on: F.date(2026, 10, 10))
        let parent = R.expense(500, R.food, on: F.date(2026, 10, 5))
        let entries = SpendingReportBuilder.entries(
            in: R.snapshot([older, newer, refund, parent]),
            period: .thisMonth,
            today: R.today,
            currencyCode: "INR",
            categoryID: R.groceries.id,
        )
        #expect(entries.map(\.id) == [newer.id, refund.id, older.id])
        #expect(entries.map(\.amount) == [1_240, -100, 2_000])
        #expect(entries.first?.account.id == F.savingsID)
    }
}

@Suite("Report shares (#27, largest remainder)")
struct ReportSharesTests {
    @Test("Shares add up to exactly 100.0%")
    func addUp() throws {
        let shares = try #require(ReportShares.tenths(of: [1, 1, 1], total: 3))
        #expect(shares == [334, 333, 333])
        let fixture: [Decimal] = [45_000, Decimal(string: "12450.50")!, 3_200]
        let fixtureShares = try #require(ReportShares.tenths(of: fixture, total: Decimal(string: "60650.50")!))
        #expect(fixtureShares.reduce(0, +) == 1000)
        #expect(fixtureShares == [742, 205, 53])
    }

    @Test("A negative amount gets a negative share and the shares still add up to 1000")
    func negative() throws {
        let shares = try #require(ReportShares.tenths(of: [1_000, -300], total: 700))
        #expect(shares == [1429, -429])
    }

    @Test("No shares when the total isn't above 0")
    func noTotal() {
        #expect(ReportShares.tenths(of: [-300], total: -300) == nil)
        #expect(ReportShares.tenths(of: [], total: 0) == nil)
    }
}

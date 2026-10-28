import Foundation
import LittleOrbitDomain
import Testing

/// “Where do I spend the most?” (#184 slice 4): spending grouped by payee, counted exactly as the category
/// report counts it, so the totals agree for the same filters. Made-up data only.
@Suite("Spending by payee (#184 slice 4)")
struct PayeeSpendingReportTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = ReportFixture  // swiftlint:disable:this type_name

    static let sunrise = Payee(name: "Sunrise Apartments")
    static let basket = Payee(name: "Green Basket")
    static let trailhead = Payee(name: "Trailhead Sports")
    static let gone: Payee = {
        var payee = Payee(name: "Closed Kiosk")
        payee.deletedAt = F.date(2026, 9, 1)
        return payee
    }()

    static let october = ReportDayRange.month(year: 2026, month: 10)

    static func expense(_ amount: Decimal, _ payee: Payee?, day: Int, category: TransactionCategory? = R.rent)
        -> Transaction
    {
        var transaction = R.expense(amount, category, on: F.date(2026, 10, day))
        transaction.payeeID = payee?.id
        return transaction
    }

    static func refund(_ amount: Decimal, _ payee: Payee?, day: Int) -> Transaction {
        var transaction = R.refund(amount, R.electronics, on: F.date(2026, 10, day))
        transaction.payeeID = payee?.id
        return transaction
    }

    static func snapshot(_ transactions: [Transaction], splits: [TransactionSplit] = []) -> LedgerSnapshot {
        var snapshot = R.snapshot(transactions, splits: splits)
        snapshot.payees = [sunrise, basket, trailhead, gone]
        return snapshot
    }

    static func query(_ accounts: ReportAccountFilter = .all) -> SpendingReportQuery {
        SpendingReportQuery(range: october, currencyCode: "INR", accounts: accounts, grouping: .payee)
    }

    static func report(_ snapshot: LedgerSnapshot, _ query: SpendingReportQuery = query()) -> SpendingReport {
        SpendingReportBuilder.report(in: snapshot, query: query, defaultCurrency: "INR")
    }

    @Test("Given expenses at three payees, then each payee's total matches its transactions, largest first")
    func threePayees() {
        let report = Self.report(
            Self.snapshot([
                Self.expense(45_000, Self.sunrise, day: 1),
                Self.expense(2_000, Self.basket, day: 3, category: R.groceries),
                Self.expense(450.50, Self.basket, day: 9, category: R.groceries),
                Self.expense(5_000, Self.trailhead, day: 12, category: R.electronics),
            ])
        )
        #expect(report.rows.map(\.payee?.name) == ["Sunrise Apartments", "Trailhead Sports", "Green Basket"])
        #expect(report.rows.map(\.amount) == [45_000, 5_000, 2_450.50])
        #expect(report.rows.map(\.transactionCount) == [1, 1, 2])
        #expect(report.rows.map(\.id) == [Self.sunrise.id, Self.trailhead.id, Self.basket.id])
        #expect(report.rows.allSatisfy { $0.categoryID == nil && $0.category == nil })
        #expect(report.total == 52_450.50)
        #expect(report.rows.compactMap(\.shareTenths).reduce(0, +) == 1_000)
    }

    @Test("Given a payee's drill-down, then it lists only that payee's transactions, adding up to its row")
    func drillDown() {
        let snapshot = Self.snapshot([
            Self.expense(45_000, Self.sunrise, day: 1),
            Self.expense(2_000, Self.basket, day: 3),
            Self.expense(450.50, Self.basket, day: 9),
            Self.refund(100, Self.basket, day: 10),
        ])
        let entries = SpendingReportBuilder.entries(in: snapshot, query: Self.query(), rowID: Self.basket.id)
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.transaction.payeeID == Self.basket.id })
        #expect(entries.reduce(Decimal(0)) { $0 + $1.amount } == 2_350.50)
        #expect(entries.first?.day == F.day(2026, 10, 10))
    }

    @Test("Transactions with no payee, or whose payee was deleted, group in one No Payee row, with its drill-down")
    func noPayee() {
        let snapshot = Self.snapshot([
            Self.expense(300, nil, day: 2),
            Self.expense(200, Self.gone, day: 4),
            Self.expense(1_000, Self.sunrise, day: 5),
        ])
        let report = Self.report(snapshot)
        #expect(report.rows.count == 2)
        let none = report.rows[1]
        #expect(none.payeeID == nil && none.payee == nil && none.id == nil)
        #expect(none.amount == 500)
        #expect(none.transactionCount == 2)
        let entries = SpendingReportBuilder.entries(in: snapshot, query: Self.query(), rowID: nil)
        #expect(entries.map(\.amount).sorted() == [200, 300])
    }

    @Test("D420.6: a refund lowers its own payee, even when its original expense was at another payee")
    func refundOwnPayee() {
        var original = Self.expense(2_000, Self.basket, day: 1)
        original.categoryID = R.electronics.id
        var refund = Self.refund(500, Self.trailhead, day: 3)
        refund.refundOfID = original.id
        let report = Self.report(Self.snapshot([original, refund, Self.expense(1_000, Self.trailhead, day: 2)]))
        #expect(report.rows.map(\.payee?.name) == ["Green Basket", "Trailhead Sports"])
        #expect(report.rows.map(\.amount) == [2_000, 500])
        #expect(report.rows[1].transactionCount == 2)
    }

    @Test("D420.6: refunds over spending show the signed net, below the zero rows, counted in the total")
    func refundsOverSpending() {
        let report = Self.report(
            Self.snapshot([
                Self.expense(1_000, Self.sunrise, day: 1),
                Self.expense(200, Self.basket, day: 2),
                Self.refund(200, Self.basket, day: 3),
                Self.refund(300, Self.trailhead, day: 4),
            ])
        )
        #expect(report.rows.map(\.payee?.name) == ["Sunrise Apartments", "Green Basket", "Trailhead Sports"])
        #expect(report.rows.map(\.amount) == [1_000, 0, -300])
        #expect(report.total == 700)
        #expect(report.rows.last?.shareTenths.map { $0 < 0 } == true)
        #expect(report.chartBars.count == 1)
    }

    @Test("A split expense counts once at its payee, with all its lines")
    func splitExpense() {
        let expense = Self.expense(1_500, Self.basket, day: 6, category: nil)
        let splits = [
            TransactionSplit(transactionID: expense.id, categoryID: R.groceries.id, amount: 1_000),
            TransactionSplit(transactionID: expense.id, categoryID: R.household.id, amount: 500),
        ]
        let report = Self.report(Self.snapshot([expense], splits: splits))
        #expect(report.rows.count == 1)
        #expect(report.rows.first?.amount == 1_500)
        #expect(report.rows.first?.transactionCount == 1)
    }

    @Test("Transfers and plain income aren't spending; the payee total equals the category total")
    func agreesWithCategories() {
        var income = F.income(80_000, on: F.date(2026, 10, 1))
        income.payeeID = Self.sunrise.id
        let transactions = [
            Self.expense(45_000, Self.sunrise, day: 1),
            Self.expense(2_000, Self.basket, day: 3, category: R.groceries),
            Self.refund(300, Self.trailhead, day: 4),
            Self.expense(700, nil, day: 5, category: nil),
            income,
            F.transfer(20_000, on: F.date(2026, 10, 5)),
        ]
        let snapshot = Self.snapshot(transactions)
        let byPayee = Self.report(snapshot)
        var categoryQuery = Self.query()
        categoryQuery.grouping = .category
        let byCategory = Self.report(snapshot, categoryQuery)
        #expect(byPayee.total == 47_400)
        #expect(byPayee.total == byCategory.total)
        #expect(byPayee.rows.map(\.amount).reduce(0, +) == byPayee.total)
    }

    @Test("D417: a hidden account's spending counts until it's unticked")
    func hiddenAccount() {
        var snapshot = Self.snapshot([
            Self.expense(1_000, Self.sunrise, day: 1),
            {
                var transaction = Self.expense(500, Self.basket, day: 2)
                transaction.accountID = F.walletID
                return transaction
            }(),
        ])
        snapshot.accounts = snapshot.accounts.map { account in
            var copy = account
            copy.isHidden = account.id == F.walletID
            return copy
        }
        #expect(Self.report(snapshot).total == 1_500)
        let unticked = Self.report(snapshot, Self.query(ReportAccountFilter(unticked: [F.walletID])))
        #expect(unticked.total == 1_000)
        #expect(unticked.rows.map(\.payee?.name) == ["Sunrise Apartments"])
    }

    @Test("Ties sort by payee name, No Payee last among equals")
    func ties() {
        let report = Self.report(
            Self.snapshot([
                Self.expense(100, nil, day: 1),
                Self.expense(100, Self.trailhead, day: 2),
                Self.expense(100, Self.basket, day: 3),
            ])
        )
        #expect(report.rows.map(\.payee?.name) == ["Green Basket", "Trailhead Sports", nil])
    }
}

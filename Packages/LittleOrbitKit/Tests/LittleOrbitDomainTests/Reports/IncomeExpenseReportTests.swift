import Foundation
import LittleOrbitDomain
import Testing

/// “How much do I earn compared to my expenses?” (#184 slice 5, D420): income and expenses per calendar month.
/// Each month equals the income and spending reports for that month and accounts (S46, S49).
@Suite("Income vs expenses by month (#184 slice 5)")
struct IncomeExpenseReportTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = ReportFixture  // swiftlint:disable:this type_name
    typealias I = IncomeFixture  // swiftlint:disable:this type_name

    static let sixMonths = ReportPeriod.lastSixMonths.range(today: R.today)

    static func report(
        _ snapshot: LedgerSnapshot,
        range: ReportDayRange = sixMonths,
        currency: String? = nil,
        accounts: ReportAccountFilter = .all,
    ) -> IncomeExpenseReport {
        IncomeExpenseReportBuilder.report(
            in: snapshot,
            query: SpendingReportQuery(range: range, currencyCode: currency, accounts: accounts),
            defaultCurrency: "INR",
        )
    }

    static var transactions: [Transaction] {
        I.october + [
            I.income(150_000, R.salary, on: F.date(2026, 9, 1)),
            R.expense(60_000, R.rent, on: F.date(2026, 9, 2)),
            R.refund(1_000, R.rent, on: F.date(2026, 9, 9)),
            R.expense(20_000, R.rent, on: F.date(2026, 6, 2)),
            // Outside the six months.
            I.income(99_000, R.salary, on: F.date(2026, 4, 30)),
        ]
    }

    @Test("Last 6 Months has six months, oldest first; a month with nothing is 0 and 0")
    func months() {
        let report = Self.report(I.snapshot(Self.transactions))
        #expect(report.months.map(\.range.start.month) == [5, 6, 7, 8, 9, 10])
        #expect(report.months.map(\.income) == [0, 0, 0, 0, 150_000, 162_000])
        #expect(report.months.map(\.expenses) == [0, 20_000, 0, 0, 59_000, 73_448.50])
        #expect(report.months[0].leftOver == 0)
        #expect(report.months[5].leftOver == 88_551.50)
        #expect(!report.isEmpty)
    }

    @Test("The totals are the sums of the months, and left over is earned minus spent")
    func totals() {
        let report = Self.report(I.snapshot(Self.transactions))
        #expect(report.income == 312_000)
        #expect(report.expenses == Decimal(string: "152448.50"))
        #expect(report.leftOver == Decimal(string: "159551.50"))
    }

    @Test("Every month equals the income and spending reports for that month and accounts (S46, S49)")
    func agreesWithReports() {
        let snapshot = I.snapshot(Self.transactions)
        let accounts = ReportAccountFilter(unticked: [F.walletID])
        let report = Self.report(snapshot, currency: "INR", accounts: accounts)
        for month in report.months {
            let income = SpendingReportBuilder.report(
                in: snapshot,
                query: SpendingReportQuery(range: month.range, currencyCode: "INR", accounts: accounts, flow: .income),
                defaultCurrency: "INR",
            )
            let spending = SpendingReportBuilder.report(
                in: snapshot,
                query: SpendingReportQuery(range: month.range, currencyCode: "INR", accounts: accounts),
                defaultCurrency: "INR",
            )
            #expect(month.income == income.total)
            #expect(month.expenses == spending.total)
        }
    }

    @Test("A custom range's first and last months count only their included days")
    func customRange() {
        let range = ReportDayRange(start: F.day(2026, 9, 2), end: F.day(2026, 10, 5))
        let report = Self.report(I.snapshot(Self.transactions), range: range)
        #expect(report.months.map(\.income) == [0, 160_000])
        #expect(report.months.map(\.expenses) == [59_000, 73_748.50])
    }

    @Test("Currencies come from income and spending, the default first; a picked one is kept; never added together")
    func currencies() {
        let snapshot = I.snapshot([
            I.income(1_000, R.salary, on: F.date(2026, 10, 1), account: F.usdID),
            R.expense(700, R.rent, on: F.date(2026, 10, 2), account: F.jpyID),
            R.expense(100, R.rent, on: F.date(2026, 10, 2)),
        ])
        let report = Self.report(snapshot)
        #expect(report.currencies == ["INR", "JPY", "USD"])
        #expect(report.currencyCode == "INR")
        #expect(report.expenses == 100)
        let usd = Self.report(snapshot, currency: "USD")
        #expect(usd.currencyCode == "USD")
        #expect(usd.income == 1_000 && usd.expenses == 0)
        #expect(usd.accounts.map(\.account.name) == ["USD Wallet"])
    }

    @Test("Empty only when the whole range has no income and no expenses")
    func empty() {
        #expect(Self.report(I.snapshot([])).isEmpty)
        #expect(Self.report(I.snapshot([I.income(1, R.salary, on: F.date(2026, 5, 1))])).isEmpty == false)
        #expect(Self.report(I.snapshot([R.refund(5, R.rent, on: F.date(2026, 5, 1))])).isEmpty == false)
        #expect(Self.report(I.snapshot([F.transfer(500, on: F.date(2026, 5, 1))])).isEmpty)
        #expect(Self.report(I.snapshot([])).months.count == 6)
    }

    @Test("Hidden accounts count by default; future-dated items count in their own month (D417)")
    func hiddenAndFuture() {
        var snapshot = I.snapshot([
            I.income(400, R.salary, on: F.date(2026, 10, 30), account: F.walletID),
            R.expense(100, R.rent, on: F.date(2026, 10, 29), account: F.walletID),
        ])
        snapshot.accounts = snapshot.accounts.map { account in
            var copy = account
            copy.isHidden = copy.id == F.walletID
            return copy
        }
        let report = Self.report(snapshot)
        #expect(report.months.last?.income == 400)
        #expect(report.months.last?.expenses == 100)
        #expect(Self.report(snapshot, accounts: ReportAccountFilter(unticked: [F.walletID])).income == 0)
    }
}

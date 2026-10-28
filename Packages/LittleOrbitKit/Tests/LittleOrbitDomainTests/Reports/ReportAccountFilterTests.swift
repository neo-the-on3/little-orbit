import Foundation
import LittleOrbitDomain
import Testing

@Suite("Spending report account filter and custom ranges (#184, D417)")
struct ReportAccountFilterTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = ReportFixture  // swiftlint:disable:this type_name

    static let october = ReportDayRange.month(year: 2026, month: 10)

    /// Everyday Savings and Corner Wallet (INR), USD Wallet and Yen Pocket, with Corner Wallet hidden.
    static func snapshot(_ transactions: [Transaction]) -> LedgerSnapshot {
        var snapshot = R.snapshot(transactions)
        snapshot.accounts = snapshot.accounts.map { account in
            var copy = account
            copy.isHidden = account.id == F.walletID
            return copy
        }
        return snapshot
    }

    static func report(_ snapshot: LedgerSnapshot, _ query: SpendingReportQuery) -> SpendingReport {
        SpendingReportBuilder.report(in: snapshot, query: query, defaultCurrency: "INR")
    }

    @Test("Given INR and USD accounts, when INR is shown, then the filter lists only the INR accounts, by name")
    func listsShownCurrency() {
        let snapshot = Self.snapshot([
            R.expense(100, R.rent, on: F.date(2026, 10, 1)),
            R.expense(5, R.rent, on: F.date(2026, 10, 1), account: F.usdID),
        ])
        let report = Self.report(snapshot, SpendingReportQuery(range: Self.october))
        #expect(report.accounts.map(\.account.name) == ["Corner Wallet", "Everyday Savings"])
        #expect(report.accounts.allSatisfy { $0.isIncluded })
        #expect(report.countsAllAccounts)
        let usd = Self.report(snapshot, SpendingReportQuery(range: Self.october, currencyCode: "USD"))
        #expect(usd.accounts.map(\.account.name) == ["USD Wallet"])
    }

    @Test("Given a hidden INR account with ₹500.00 spent, it's listed, ticked and counted until it's unticked (D417)")
    func hiddenCountsUntilUnticked() {
        let snapshot = Self.snapshot([
            R.expense(1_000, R.rent, on: F.date(2026, 10, 1)),
            R.expense(500, R.groceries, on: F.date(2026, 10, 2), account: F.walletID),
        ])
        let all = Self.report(snapshot, SpendingReportQuery(range: Self.october))
        #expect(all.total == 1_500)
        #expect(all.accounts.first { $0.id == F.walletID }?.isIncluded == true)

        var filter = ReportAccountFilter.all
        filter.set(false, for: F.walletID)
        let unticked = Self.report(snapshot, SpendingReportQuery(range: Self.october, accounts: filter))
        #expect(unticked.total == 1_000)
        #expect(unticked.rows.map(\.categoryID) == [R.rent.id])
        #expect(unticked.accounts.first { $0.id == F.walletID }?.isIncluded == false)
        #expect(!unticked.countsAllAccounts)

        filter.set(true, for: F.walletID)
        #expect(filter == .all)
        #expect(Self.report(snapshot, SpendingReportQuery(range: Self.october, accounts: filter)).total == 1_500)
    }

    // The view model never sends this query: the last ticked account can't be unticked (UI Designer's B1 on #307;
    // SpendingReportFiltersTests.lastTickedAccount). The builder still keeps the currency if one arrives.
    @Test("A query that unticks every INR account still leaves INR on the currency picker")
    func currencyStaysWhenUnticked() {
        let snapshot = Self.snapshot([
            R.expense(100, R.rent, on: F.date(2026, 10, 1)),
            R.expense(5, R.rent, on: F.date(2026, 10, 1), account: F.usdID),
        ])
        let filter = ReportAccountFilter(unticked: [F.savingsID, F.walletID])
        let report = Self.report(
            snapshot,
            SpendingReportQuery(range: Self.october, currencyCode: "INR", accounts: filter),
        )
        #expect(report.currencies == ["INR", "USD"])
        #expect(report.currencyCode == "INR")
        #expect(report.isEmpty)
        #expect(report.accounts.count == 2)
    }

    @Test("A drill-down query with no currency falls back to the given default currency, as the report does (N3)")
    func entriesDefaultCurrency() {
        let snapshot = Self.snapshot([
            R.expense(100, R.rent, on: F.date(2026, 10, 1)),
            R.expense(5, R.rent, on: F.date(2026, 10, 1), account: F.usdID),
        ])
        let query = SpendingReportQuery(range: Self.october)
        let usd = SpendingReportBuilder.entries(
            in: snapshot,
            query: query,
            categoryID: R.rent.id,
            defaultCurrency: "USD",
        )
        #expect(usd.map(\.amount) == [5])
        let inr = SpendingReportBuilder.entries(
            in: snapshot,
            query: query,
            categoryID: R.rent.id,
            defaultCurrency: "INR",
        )
        #expect(inr.map(\.amount) == [100])
    }

    @Test("Given I untick one account, then the drill-down lists only the ticked accounts' transactions")
    func drillDownFollowsFilter() {
        let snapshot = Self.snapshot([
            R.expense(1_000, R.rent, on: F.date(2026, 10, 1)),
            R.expense(500, R.rent, on: F.date(2026, 10, 2), account: F.walletID),
        ])
        let query = SpendingReportQuery(
            range: Self.october,
            currencyCode: "INR",
            accounts: ReportAccountFilter(unticked: [F.walletID]),
        )
        let entries = SpendingReportBuilder.entries(in: snapshot, query: query, categoryID: R.rent.id)
        #expect(entries.map(\.amount) == [1_000])
        #expect(entries.map(\.account.id) == [F.savingsID])
    }

    @Test("Given ₹100.00 on 15 Sep and ₹200.00 on 14 Oct 2026, a custom 15 Sep–14 Oct range totals ₹300.00")
    func customRangeIncludesBothEnds() {
        let snapshot = Self.snapshot([
            R.expense(50, R.rent, on: F.date(2026, 9, 14)),
            R.expense(100, R.rent, on: F.date(2026, 9, 15)),
            R.expense(200, R.rent, on: F.date(2026, 10, 14)),
            R.expense(70, R.rent, on: F.date(2026, 10, 15)),
        ])
        let range = ReportDayRange(start: F.day(2026, 9, 15), end: F.day(2026, 10, 14))
        let report = Self.report(snapshot, SpendingReportQuery(range: range))
        #expect(report.total == 300)
        #expect(report.range == range)
    }

    @Test("The off-main helper returns the work's result and throws when its caller is cancelled")
    func offMain() async throws {
        let answer = try await ReportWork.offMain { 40 + 2 }
        #expect(answer == 42)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ReportWork.offMain { 1 }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

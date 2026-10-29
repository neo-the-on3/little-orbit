import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// “How much do I earn compared to my expenses?” (#184 slice 5, D420): income and expenses per month, with the
/// slice 1 filters. Made-up data only.
@MainActor
@Suite("Income vs expenses view model (#184 slice 5)")
struct IncomeExpenseReportViewModelTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name
    typealias I = IncomeFixtureFeatures  // swiftlint:disable:this type_name

    static func plain(_ text: String) -> String { SpendingReportFiltersTests.plain(text) }

    /// “US$40.00” or “$40.00”, as the platform's ICU writes US dollars in en_IN.
    static let usd40 = Decimal(40).formatted(.currency(code: "USD").locale(SpendingFixture.locale))

    static func model(_ useCase: any LoadSpendingReportUseCase) -> IncomeExpenseReportViewModel {
        IncomeExpenseReportViewModel(
            useCase: useCase,
            locale: S.locale,
            timeZone: TimeZone(identifier: S.zone)!,
            now: { S.date(10, 25) },
        )
    }

    /// October's fixture, plus September's ₹1,50,000.00 salary and ₹60,000.00 rent less a ₹1,000.00 refund,
    /// and June's ₹20,000.00 rent.
    static var transactions: [Transaction] {
        I.october + [
            I.income("150000", I.salary, 9, 1),
            S.expense("60000", S.rent, 9, 2),
            S.refund("1000", S.rent, 9, 9),
            S.expense("20000", S.rent, 6, 2),
        ]
    }

    @Test("Last 6 Months is the default, with This Year, Last Year and Custom…; the wording is the spec's")
    func defaults() async {
        let fake = FakeSpendingReportUseCase(snapshot: I.snapshot(Self.transactions))
        let model = Self.model(fake)
        #expect(model.isLoading)
        await model.load()
        #expect(model.period == .lastSixMonths)
        #expect(Self.plain(model.periodTitle) == "May – Oct 2026")
        #expect(model.periods.map(model.periodName) == ["Last 6 Months", "This Year", "Last Year"])
        #expect(model.question == "How much do I earn compared to my expenses?")
        #expect(model.navigationTitle == "Income vs Expenses")
        #expect(
            model.footer
                == "Transfers between your own accounts aren’t counted. Refunds reduce expenses and are never income."
        )
        #expect(
            fake.incomeExpenseRequests.last?.range
                == ReportPeriod.lastSixMonths.range(today: .init(year: 2026, month: 10, day: 25))
        )
    }

    @Test("The header shows Earned, Spent and Left over for the range, Left over signed")
    func header() async {
        let model = Self.model(FakeSpendingReportUseCase(snapshot: I.snapshot(Self.transactions)))
        await model.load()
        #expect(model.values.map(\.label) == ["Earned", "Spent", "Left over"])
        #expect(model.values.map(\.amountText) == ["₹3,12,000.00", "₹1,52,448.50", "+₹1,59,551.50"])
        #expect(
            model.values.map(\.accessibilityLabel) == [
                "Earned, ₹3,12,000.00", "Spent, ₹1,52,448.50", "Left over, +₹1,59,551.50",
            ]
        )
        #expect(Self.plain(model.caption) == "May – Oct 2026 · all accounts · INR")
    }

    @Test("Rows: newest month first, left over trailing, “In … · Out …” below, read as one line")
    func rows() async throws {
        let model = Self.model(FakeSpendingReportUseCase(snapshot: I.snapshot(Self.transactions)))
        await model.load()
        #expect(model.rows.map(\.title) == ["Oct 2026", "Sep 2026", "Aug 2026", "Jul 2026", "Jun 2026", "May 2026"])
        let october = try #require(model.rows.first)
        #expect(october.leftOverText == "+₹88,551.50")
        #expect(october.leftOverTone == .positive)
        #expect(october.subtitle == "In ₹1,62,000.00 · Out ₹73,448.50")
        #expect(
            october.accessibilityLabel
                == "October 2026, left over ₹88,551.50, income ₹1,62,000.00, expenses ₹73,448.50"
        )
        let june = model.rows[4]
        #expect(june.leftOverText == "−₹20,000.00")
        #expect(june.leftOverTone == .negative)
        let may = try #require(model.rows.last)
        #expect(may.leftOverText == "₹0.00")
        #expect(may.subtitle == "In ₹0.00 · Out ₹0.00")
    }

    @Test("The Mac table: Month | Income | Expenses | Left over, oldest first, then a Total row")
    func table() async throws {
        let model = Self.model(FakeSpendingReportUseCase(snapshot: I.snapshot(Self.transactions)))
        await model.load()
        #expect(model.monthColumn == "Month")
        #expect(model.incomeColumn == "Income")
        #expect(model.expensesColumn == "Expenses")
        #expect(model.leftOverColumn == "Left over")
        #expect(
            model.tableRows.map(\.title) == [
                "May 2026", "Jun 2026", "Jul 2026", "Aug 2026", "Sep 2026", "Oct 2026", "Total",
            ]
        )
        let total = try #require(model.tableRows.last)
        #expect(total.isTotal)
        #expect(total.incomeText == "₹3,12,000.00")
        #expect(total.expensesText == "₹1,52,448.50")
        #expect(total.leftOverText == "+₹1,59,551.50")
        #expect(model.tableRows.dropLast().allSatisfy { !$0.isTotal })
    }

    @Test("The chart: two bars a month, Income and Expenses, months with nothing at 0, and a two-series audio graph")
    func chart() async {
        let model = Self.model(FakeSpendingReportUseCase(snapshot: I.snapshot(Self.transactions)))
        await model.load()
        #expect(model.chartBars.count == 12)
        #expect(model.incomeSeries == "Income")
        #expect(model.expensesSeries == "Expenses")
        #expect(Set(model.chartBars.map(\.series)) == ["Income", "Expenses"])
        let october = model.chartBars.filter { $0.monthTitle == "October 2026" }
        #expect(october.map(\.amount) == [162_000, 73_448.5])
        #expect(october.map(\.amountText) == ["₹1,62,000.00", "₹73,448.50"])
        #expect(model.chartBars.filter { $0.monthTitle == "May 2026" }.map(\.amount) == [0, 0])
        #expect(model.chartTitle == "How much do I earn compared to my expenses?")
        #expect(model.chartSummary == model.caption)
    }

    @Test("‹ steps six months back; This Year has twelve months")
    func periods() async {
        let model = Self.model(FakeSpendingReportUseCase(snapshot: I.snapshot(Self.transactions)))
        await model.load()
        await model.step(by: -1)
        #expect(Self.plain(model.periodTitle) == "Nov 2025 – Apr 2026")
        #expect(model.isStepped)
        await model.select(.thisYear)
        #expect(model.periodTitle == "2026")
        #expect(model.rows.count == 12)
        await model.selectCustomRange(from: S.date(9, 2), to: S.date(10, 5))
        #expect(model.rows.map(\.subtitle) == ["In ₹1,60,000.00 · Out ₹73,748.50", "In ₹0.00 · Out ₹59,000.00"])
    }

    @Test("Empty only when the whole range has no income and no expenses; a transfer alone is nothing")
    func empty() async {
        let model = Self.model(FakeSpendingReportUseCase(snapshot: I.snapshot([I.transfer("500", 10, 3)])))
        await model.load()
        #expect(model.isEmpty)
        #expect(model.emptyTitle == "No Income or Expenses")
        #expect(model.emptyMessage == "There’s nothing to compare in this period. Try another period.")
    }

    @Test("Each month equals the income and spending reports for that month and accounts (S46, S49)")
    func agreesWithReports() async throws {
        let fake = FakeSpendingReportUseCase(snapshot: I.snapshot(Self.transactions))
        let model = Self.model(fake)
        await model.load()
        let income = IncomeReportViewModelTests.model(fake)
        let spending = S.model(fake)
        await income.select(.lastMonth)
        await spending.select(.lastMonth)
        #expect(model.rows[1].subtitle == "In \(income.totalText) · Out \(spending.totalText)")
    }

    @Test("A picked currency sticks while the report is open; unticking an account removes it")
    func currencyAndAccounts() async {
        let rewards = Account(name: "Rewards Card", type: .creditCard, currencyCode: "INR", isHidden: true)
        var snapshot = I.snapshot([
            I.income("1000", I.salary, 10, 1),
            S.expense("250", S.rent, 10, 3, account: rewards),
            I.income("40", I.salary, 10, 2, account: S.usdWallet),
        ])
        snapshot.accounts.append(rewards)
        let fake = FakeSpendingReportUseCase(snapshot: snapshot)
        let model = Self.model(fake)
        await model.load()
        #expect(model.currencies == ["INR", "USD"])
        #expect(model.showsCurrencyPicker)
        // The hidden card counts by default (D417).
        #expect(model.values.map(\.amountText) == ["₹1,000.00", "₹250.00", "+₹750.00"])
        await model.setAccount(rewards.id, included: false)
        #expect(model.values[1].amountText == "₹0.00")
        #expect(Self.plain(model.caption) == "May – Oct 2026 · 1 of 2 accounts · INR")
        await model.selectCurrency("USD")
        await model.load(at: 7)
        #expect(model.currencyCode == "USD")
        #expect(model.values[0].amountText == Self.usd40)
    }

    @Test("A failed read shows Couldn’t Load Report, and Try Again reloads")
    func loadFailure() async {
        let fake = FakeSpendingReportUseCase(snapshot: I.snapshot(Self.transactions))
        fake.fails = true
        let model = Self.model(fake)
        await model.load()
        #expect(model.loadFailed)
        #expect(model.loadFailedTitle == "Couldn’t Load Report")
        fake.fails = false
        await model.retry()
        #expect(!model.loadFailed)
        #expect(model.rows.count == 6)
    }

    @Test("Of two overlapping loads, only the newest is shown")
    func staleLoad() async {
        let gated = GatedSpendingReportUseCase(snapshot: I.snapshot(Self.transactions))
        let model = Self.model(gated)
        gated.gated = true
        let first = Task { await model.load() }
        await gated.waitUntilHeld(1)
        let second = Task { await model.select(.thisYear) }
        await gated.waitUntilHeld(2)
        gated.release(2)
        await second.value
        gated.releaseAll()
        await first.value
        #expect(model.periodTitle == "2026")
        #expect(model.rows.count == 12)
    }

    @Test("Reports makes it, with its question for the Reports list")
    func feature() {
        let feature = ReportsFeature(
            spendingReport: FakeSpendingReportUseCase(snapshot: S.snapshot([])),
            updates: LedgerUpdates(),
        )
        #expect(feature.incomeExpenseQuestion == "How much do I earn compared to my expenses?")
        #expect(feature.makeIncomeExpenseReport().period == .lastSixMonths)
    }
}

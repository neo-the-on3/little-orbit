import Foundation
import LittleOrbitDomain
import Observation

/// “How much do I earn compared to my expenses?” (#184 slice 5, D420) for iOS and macOS: income and expenses
/// per calendar month, with the slice 1 filters. It depends only on `LoadSpendingReportUseCase`, and its reads
/// are async, so the report is built off the main actor. Tapping a month does nothing in 1.0.
@MainActor
@Observable
public final class IncomeExpenseReportViewModel: ReportFilterModel {
    /// Last 6 Months by default (UI Designer's slice 5 spec).
    public internal(set) var selection: ReportSelection = .preset(.lastSixMonths)
    public internal(set) var accountFilter: ReportAccountFilter = .all

    /// Earned, Spent and Left over for the whole range.
    public private(set) var values: [ReportValueModel] = []
    /// “May – Oct 2026 · all accounts · INR”.
    public private(set) var caption = ""
    /// The iOS rows: newest month first.
    public private(set) var rows: [IncomeExpenseRowModel] = []
    /// The Mac table: oldest month first, then the Total row.
    public private(set) var tableRows: [IncomeExpenseRowModel] = []
    /// Two bars a month, Income then Expenses, oldest month first.
    public private(set) var chartBars: [IncomeExpenseChartBar] = []
    public private(set) var periodTitle = ""
    public private(set) var currencies: [String] = []
    public private(set) var currencyCode = ""
    public private(set) var accounts: [ReportAccountOption] = []
    public private(set) var loadFailed = false
    /// True until the first load.
    public private(set) var isLoading = true
    public private(set) var hasActivity = false
    /// Goes up on every load.
    public private(set) var revision = 0

    @ObservationIgnored private var storeRevision: Int?
    @ObservationIgnored private var requestedCurrency: String?
    /// Counts loads, so only the latest one started is shown when two overlap.
    @ObservationIgnored private var loadCount = 0
    @ObservationIgnored private let useCase: any LoadSpendingReportUseCase
    @ObservationIgnored public let locale: Locale
    @ObservationIgnored public let timeZone: TimeZone
    @ObservationIgnored public let now: () -> Date
    @ObservationIgnored let formatter: MoneyFormatter
    @ObservationIgnored let text: TransactionText

    public init(
        useCase: any LoadSpendingReportUseCase,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.useCase = useCase
        self.locale = locale
        self.timeZone = timeZone
        self.now = now
        self.formatter = MoneyFormatter(locale: locale)
        self.text = TransactionText(locale: locale)
    }

    public var periods: [ReportPeriod] { ReportPeriod.overTimePresets }

    public var question: String { ReportText.incomeExpenseQuestion }
    public var navigationTitle: String { ReportText.incomeExpenseTitle }
    public var footer: String { ReportText.incomeExpenseFooter }
    public var chartTitle: String { question }
    public var chartSummary: String { caption }
    public var incomeSeries: String { ReportText.incomeSeries }
    public var expensesSeries: String { ReportText.expensesSeries }
    public var monthColumn: String { ReportText.monthColumn }
    public var incomeColumn: String { ReportText.incomeColumn }
    public var expensesColumn: String { ReportText.expensesColumn }
    public var leftOverColumn: String { ReportText.leftOverColumn }
    public var amountAxis: String { ReportText.amountColumn }

    /// Nothing to compare in the whole range: the empty state. A month with nothing shows ₹0.00.
    public var isEmpty: Bool { !isLoading && !loadFailed && !hasActivity }
    public var emptyTitle: String { ReportText.noIncomeOrExpensesTitle }
    public var emptyMessage: String { ReportText.noIncomeOrExpensesMessage }

    /// What the next load reads.
    var query: SpendingReportQuery {
        SpendingReportQuery(
            range: selection.range(today: today),
            currencyCode: requestedCurrency,
            accounts: accountFilter,
        )
    }

    public func select(_ selection: ReportSelection) async {
        guard selection != self.selection else {
            return
        }
        self.selection = selection
        await load()
    }

    /// A new currency ticks every account again, since the list shows only that currency's accounts.
    public func selectCurrency(_ code: String) async {
        if code != currencyCode {
            accountFilter = .all
        }
        requestedCurrency = code
        await load()
    }

    public func setAccountFilter(_ filter: ReportAccountFilter) async {
        accountFilter = filter
        await load()
    }

    /// Reads the report again. A load that's overtaken by a newer one, or cancelled, changes nothing.
    public func load() async {
        loadCount += 1
        let current = loadCount
        let query = query
        do {
            let report = try await useCase.incomeExpenseReport(query)
            guard current == loadCount else {
                return
            }
            loadFailed = false
            apply(report)
        } catch is CancellationError {
            return
        } catch {
            guard current == loadCount else {
                return
            }
            loadFailed = true
            values = []
            rows = []
            tableRows = []
            chartBars = []
            caption = ""
            currencies = []
            accounts = []
            hasActivity = false
            periodTitle = title(of: query.range)
        }
        isLoading = false
        revision += 1
    }

    /// Loads again after a change to the shared store at `storeRevision`, unless it's already been read.
    public func load(at storeRevision: Int) async {
        guard storeRevision != self.storeRevision else {
            return
        }
        self.storeRevision = storeRevision
        await load()
    }

    private func apply(_ report: IncomeExpenseReport) {
        currencies = report.currencies
        currencyCode = report.currencyCode
        accounts = report.accounts
        hasActivity = report.hasActivity
        periodTitle = title(of: report.range)
        caption = ReportText.scope(
            period: periodTitle,
            accounts: accountsText(report.accounts),
            currencyCode: report.currencyCode,
        )
        let code = report.currencyCode
        values = [
            value(ReportText.earned, report.income, code),
            value(ReportText.spent, report.expenses, code),
            value(ReportText.leftOver, report.leftOver, code, signed: true),
        ]
        let months = report.months.map { row(for: $0, currencyCode: code) }
        rows = months.reversed()
        tableRows = months + [total(of: report, currencyCode: code)]
        chartBars = report.months.flatMap { bars(for: $0, currencyCode: code) }
    }
}

import Foundation

/// One calendar month of “How much do I earn compared to my expenses?” (#184 slice 5, D420).
public struct IncomeExpenseMonth: Identifiable, Equatable, Sendable {
    /// The month's days, cut to the report's range: a custom range's first and last months count only their
    /// included days.
    public var range: ReportDayRange
    /// Income that isn't a refund, as “Where does my money come from?” counts it for the month.
    public var income: Decimal
    /// Expenses minus refunds, as “What do I spend my money on?” counts it for the month. Below 0 when only
    /// refunds are left.
    public var expenses: Decimal

    public var id: CalendarDay { range.start }

    /// Earned minus spent.
    public var leftOver: Decimal { income - expenses }

    public init(range: ReportDayRange, income: Decimal, expenses: Decimal) {
        self.range = range
        self.income = income
        self.expenses = expenses
    }
}

/// Income and expenses per calendar month in one currency (#184 slice 5). Each month equals the income and
/// spending reports for that month and accounts, and the totals are the sums of the months (S46, S49). The
/// Reports list's This Month summary is this report for one month.
public struct IncomeExpenseReport: Equatable, Sendable {
    public var range: ReportDayRange
    public var currencyCode: String
    /// Every currency with income or spending in the range, the default currency first, then by code.
    public var currencies: [String]
    /// Every month in the range, oldest first, months with nothing in them too.
    public var months: [IncomeExpenseMonth]
    /// The account filter's list: every account in `currencyCode`, hidden ones too (D417).
    public var accounts: [ReportAccountOption]
    /// False when the whole range has no income and no expenses or refunds in the currency.
    public var hasActivity: Bool

    public init(
        range: ReportDayRange,
        currencyCode: String,
        currencies: [String],
        months: [IncomeExpenseMonth],
        accounts: [ReportAccountOption] = [],
        hasActivity: Bool,
    ) {
        self.range = range
        self.currencyCode = currencyCode
        self.currencies = currencies
        self.months = months
        self.accounts = accounts
        self.hasActivity = hasActivity
    }

    public var income: Decimal { months.reduce(0) { $0 + $1.income } }
    public var expenses: Decimal { months.reduce(0) { $0 + $1.expenses } }
    public var leftOver: Decimal { income - expenses }
    /// Nothing to compare: the screen shows its empty state. A month with nothing in it is still shown at 0.
    public var isEmpty: Bool { !hasActivity }
}

/// Builds income vs expenses from the same counting as the income and spending reports, so the figures agree.
/// The currency follows D414 over income and spending transactions together (D420.5).
public enum IncomeExpenseReportBuilder {
    /// The report for `query`'s range, currency and accounts. Its grouping and flow don't matter.
    public static func report(
        in snapshot: LedgerSnapshot,
        query: SpendingReportQuery,
        defaultCurrency: String,
    ) -> IncomeExpenseReport {
        let range = query.range
        let spending = SpendingReportBuilder.contributions(in: snapshot, range: range, flow: .spending)
        let income = SpendingReportBuilder.contributions(in: snapshot, range: range, flow: .income)
        let (currencies, currency) = SpendingReportBuilder.pickCurrency(
            from: (spending + income).map(\.currency),
            requested: query.currencyCode,
            defaultCurrency: defaultCurrency,
        )
        func counted(_ lines: [SpendingReportBuilder.Contribution]) -> [SpendingReportBuilder.Contribution] {
            lines.filter { $0.currency == currency && query.accounts.includes($0.account.id) }
        }
        let spent = counted(spending)
        let earned = counted(income)
        func sum(_ lines: [SpendingReportBuilder.Contribution], in month: ReportDayRange) -> Decimal {
            lines.reduce(0) { month.contains($1.day) ? $0 + $1.amount : $0 }
        }
        let months = range.months.map { month in
            IncomeExpenseMonth(range: month, income: sum(earned, in: month), expenses: sum(spent, in: month))
        }
        return IncomeExpenseReport(
            range: range,
            currencyCode: currency,
            currencies: currencies,
            months: months,
            accounts: SpendingReportBuilder.accountOptions(in: snapshot, currency: currency, filter: query.accounts),
            hasActivity: !spent.isEmpty || !earned.isEmpty,
        )
    }
}

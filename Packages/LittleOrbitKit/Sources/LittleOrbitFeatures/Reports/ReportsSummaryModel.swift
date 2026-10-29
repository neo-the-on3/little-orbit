import Foundation
import LittleOrbitDomain
import Observation

/// The Reports list's period summary (#184 slice 5): Spent, Earned and Left over for This Month, from the same
/// calculation as income vs expenses, every account counted, hidden ones too (D417). Its currency follows D414
/// over income and spending (D420.5); one the person picks stays while Reports is open.
@MainActor
@Observable
public final class ReportsSummaryModel {
    /// Spent, Earned and Left over.
    public private(set) var values: [ReportValueModel] = []
    /// “Earned − spent, October 2026 · INR”.
    public private(set) var caption = ""
    public private(set) var currencies: [String] = []
    public private(set) var currencyCode = ""
    public private(set) var loadFailed = false

    @ObservationIgnored private var requestedCurrency: String?
    @ObservationIgnored private var storeRevision: Int?
    @ObservationIgnored private var loadCount = 0
    @ObservationIgnored private let useCase: any LoadSpendingReportUseCase
    @ObservationIgnored private let formatter: MoneyFormatter
    @ObservationIgnored private let text: TransactionText
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let now: () -> Date

    public init(
        useCase: any LoadSpendingReportUseCase,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.useCase = useCase
        self.formatter = MoneyFormatter(locale: locale)
        self.text = TransactionText(locale: locale)
        self.timeZone = timeZone
        self.now = now
    }

    /// The segmented currency picker shows only with 2 or more currencies.
    public var showsCurrencyPicker: Bool { currencies.count > 1 }
    public var currencyLabel: String { ReportText.currency }

    /// Shows `code` and keeps it while Reports is open.
    public func selectCurrency(_ code: String) async {
        requestedCurrency = code
        await load()
    }

    public func load() async {
        loadCount += 1
        let current = loadCount
        let today = TransactionTiming.today(now(), timeZone: timeZone)
        let query = SpendingReportQuery(
            range: ReportPeriod.thisMonth.range(today: today),
            currencyCode: requestedCurrency,
        )
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
            caption = ""
            currencies = []
        }
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
        let code = report.currencyCode
        values = [
            value(ReportText.spent, report.expenses, code),
            value(ReportText.earned, report.income, code),
            value(ReportText.leftOver, report.leftOver, code, signed: true),
        ]
        caption = ReportText.summaryCaption(
            period: text.format(report.range.start, template: "MMMMyyyy"),
            currencyCode: code,
        )
    }

    private func value(_ label: String, _ amount: Decimal, _ code: String, signed: Bool = false) -> ReportValueModel {
        let amountText = formatter.string(amount, currencyCode: code, showsPlus: signed)
        return ReportValueModel(
            label: label,
            amountText: amountText,
            amountTone: signed ? IncomeExpenseReportViewModel.tone(of: amount) : .neutral,
            accessibilityLabel: ReportText.valueSpoken(label, amountText),
        )
    }
}

import Foundation
import LittleOrbitDomain
import Observation

/// One category row of the spending report, ready for the list and VoiceOver.
public struct SpendingRowModel: Identifiable, Equatable, Sendable {
    /// `nil` for Uncategorised.
    public var categoryID: UUID?
    /// “Rent”, “Food & Dining › Groceries” or “Uncategorised”.
    public var name: String
    public var symbolName: String
    public var hue: CategoryHue
    public var amountText: String
    /// “16.9%”, or `nil` when the total isn't above 0.
    public var shareText: String?
    /// “6 transactions”.
    public var countText: String
    /// The bar's length as a fraction of the largest row, from 0 to 1. `nil` when the row is 0 or below (a
    /// refund-only row): it shows no bar, never a negative one.
    public var barFraction: Double?
    public var amountTone: AmountTone
    /// “Groceries, ₹12,450.50, Indian rupees, 16.9%, 6 transactions”: the row read as one line of a data table.
    public var accessibilityLabel: String

    public var id: UUID? { categoryID }
}

/// One transaction in a row's drill-down.
public struct SpendingEntryRowModel: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// An expense: the payee, else the description, else “Expense”. A refund: D233's title (D318.6), such as
    /// “Refund · Trailhead Sports”, “Refund (original deleted) · R1 Trailhead refund”, or just “Refund” or
    /// “Refund (original deleted)”.
    public var title: String
    /// “Everyday Savings · Tue, 20 Oct”: the account and the day.
    public var subtitle: String
    /// What it did to spending, as the frames show it: −₹1,240.00 for an expense, +₹100.00 for a refund.
    public var amountText: String
    public var amountTone: AmountTone
    public var accessibilityLabel: String
}

/// A row's drill-down: the transactions that add up to its amount (#27).
public struct SpendingDrillDown: Equatable, Sendable {
    public var title: String
    public var amountText: String
    /// “October 2026 · INR”: the report's period and currency, as the report's caption names them (D319.5).
    public var caption: String
    /// “6 transactions”.
    public var countText: String
    public var entries: [SpendingEntryRowModel]
}

/// “What do I spend my money on?” (#27 core, D316) for iOS and macOS. It depends only on
/// `LoadSpendingReportUseCase`.
@MainActor
@Observable
public final class SpendingReportViewModel {
    /// The preset period. Changing it reloads the report.
    public var period: ReportPeriod = .thisMonth {
        didSet {
            if period != oldValue {
                load()
            }
        }
    }

    public private(set) var rows: [SpendingRowModel] = []
    public private(set) var totalText = ""
    public private(set) var totalCaption = ""
    public private(set) var periodTitle = ""
    public private(set) var currencies: [String] = []
    /// The currency shown: one at a time, never added together (D17).
    public private(set) var currencyCode = ""
    public private(set) var loadFailed = false
    /// True until the first load.
    public private(set) var isLoading = true
    /// Goes up on every load, whether or not the rows changed, so an open drill-down reads its transactions
    /// again after any change to the store, such as a payee rename (Tech Architect's NB9 on #185).
    public private(set) var revision = 0

    @ObservationIgnored private var report: SpendingReport?
    @ObservationIgnored private var requestedCurrency: String?
    @ObservationIgnored private let useCase: any LoadSpendingReportUseCase
    @ObservationIgnored private let locale: Locale
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
        self.locale = locale
        self.formatter = MoneyFormatter(locale: locale)
        self.text = TransactionText(locale: locale)
        self.timeZone = timeZone
        self.now = now
    }

    /// Shows `code` and keeps it while the period changes, as long as the period has spending in it.
    public func selectCurrency(_ code: String) {
        requestedCurrency = code
        load()
    }

    public var periods: [ReportPeriod] { ReportPeriod.allCases }

    public func periodName(_ period: ReportPeriod) -> String {
        ReportText.periodName(period)
    }

    /// The picker only shows when the period has spending in more than one currency.
    public var showsCurrencyPicker: Bool { currencies.count > 1 }

    /// No expenses or refunds in this period (and currency): the empty state.
    public var isEmpty: Bool { !isLoading && !loadFailed && rows.isEmpty }

    public var emptyTitle: String { ReportText.emptyTitle }
    public var emptyMessage: String { ReportText.emptyMessage }
    public var loadFailedTitle: String { ReportText.loadFailedTitle }
    public var loadFailedMessage: String { ReportText.tryAgain }

    public func load() {
        defer {
            isLoading = false
            revision += 1
        }
        do {
            let report = try useCase.spendingReport(for: period, currencyCode: requestedCurrency)
            self.report = report
            loadFailed = false
            apply(report)
        } catch {
            report = nil
            loadFailed = true
            rows = []
            totalText = ""
            totalCaption = ""
            currencies = []
            periodTitle = title(of: period.range(today: TransactionTiming.today(now(), timeZone: timeZone)))
        }
    }

    /// The transactions behind `row`, read when its drill-down opens and again after each load. Its title is the
    /// row's current name, in case the category was renamed. `nil` if they can't be read.
    public func drillDown(for row: SpendingRowModel) -> SpendingDrillDown? {
        guard let report else {
            return nil
        }
        guard
            let entries = try? useCase.spendingEntries(
                for: report.period,
                currencyCode: report.currencyCode,
                categoryID: row.categoryID,
            )
        else {
            return nil
        }
        let today = TransactionTiming.today(now(), timeZone: timeZone)
        let total = entries.reduce(Decimal(0)) { $0 + $1.amount }
        let current = rows.first { $0.categoryID == row.categoryID } ?? row
        return SpendingDrillDown(
            title: current.name,
            amountText: formatter.string(total, currencyCode: report.currencyCode),
            caption: ReportText.drillDownCaption(
                share: current.shareText,
                period: title(of: report.range),
                currencyCode: report.currencyCode,
            ),
            countText: ReportText.transactionCount(entries.count),
            entries: entries.map { entryRow($0, currencyCode: report.currencyCode, today: today) },
        )
    }

    // MARK: - Building rows

    private func apply(_ report: SpendingReport) {
        currencies = report.currencies
        currencyCode = report.currencyCode
        periodTitle = title(of: report.range)
        totalText = formatter.string(report.total, currencyCode: report.currencyCode)
        totalCaption = ReportText.spentCaption(period: periodTitle, currencyCode: report.currencyCode)
        let largest = report.rows.map(\.amount).max() ?? 0
        rows = report.rows.map { row(for: $0, largest: largest, currencyCode: report.currencyCode) }
    }

    private func row(for row: SpendingReportRow, largest: Decimal, currencyCode: String) -> SpendingRowModel {
        let name = name(of: row)
        let amountText = formatter.string(row.amount, currencyCode: currencyCode)
        let shareText = row.shareTenths.map(shareString)
        let countText = ReportText.transactionCount(row.transactionCount)
        var barFraction: Double?
        if row.amount > 0, largest > 0 {
            let fraction = NSDecimalNumber(decimal: row.amount / largest).doubleValue
            barFraction = min(1, max(0, fraction))
        }
        let currencyName = locale.localizedString(forCurrencyCode: currencyCode)
        let spoken = [name, amountText, currencyName, shareText, countText].compactMap(\.self)
        return SpendingRowModel(
            categoryID: row.categoryID,
            name: name,
            symbolName: row.category.map(CategoryAppearance.symbol(of:)) ?? "questionmark",
            hue: row.category.map(CategoryAppearance.hue(of:)) ?? .gray,
            amountText: amountText,
            shareText: shareText,
            countText: countText,
            barFraction: barFraction,
            amountTone: row.amount < 0 ? .negative : .neutral,
            accessibilityLabel: spoken.joined(separator: ", "),
        )
    }

    private func name(of row: SpendingReportRow) -> String {
        guard let category = row.category else {
            return ReportText.uncategorised
        }
        guard let parent = row.parent else {
            return category.name
        }
        return ReportText.subcategoryName(category.name, parent: parent.name)
    }

    /// 169 tenths is “16.9%” in the view model's locale. A negative share takes the locale's own minus sign
    /// and its place from the format style, rather than one added in front (Tech Architect's NB8 on #185).
    private func shareString(_ tenths: Int) -> String {
        (Decimal(tenths) / 1000)
            .formatted(.percent.precision(.fractionLength(1)).sign(strategy: .automatic).locale(locale))
    }

    /// “October 2026” for a month, “2026” for a year, in the view model's locale.
    private func title(of range: ReportDayRange) -> String {
        let isYear = range.start.month == 1 && range.end.month == 12 && range.start.year == range.end.year
        return text.format(range.start, template: isYear ? "yyyy" : "MMMMyyyy")
    }

    private func entryRow(_ entry: SpendingReportEntry, currencyCode: String, today: CalendarDay)
        -> SpendingEntryRowModel
    {
        let transaction = entry.transaction
        // The payee, else the trimmed description (also when the payee record is gone), as the list rows (D233.1).
        let name = entry.payee?.name ?? TransactionText.trimmed(transaction.details)
        let title: String
        switch RefundStatus(of: transaction) {
        case .notRefund:
            title = name ?? ReportText.expense
        case .linked:
            title = RefundText.rowTitle(name: name, isLinked: true)
        case .originalDeleted:
            // Its expense was deleted, or it came in unlinked by CSV import (D35.2).
            title = RefundText.rowTitle(name: name, isLinked: false)
        }
        let date = text.format(entry.day, template: entry.day.year == today.year ? "EEEdMMM" : "EEEdMMMyyyy")
        let subtitle = [entry.account.name, date].joined(separator: " · ")
        let amountText = formatter.string(-entry.amount, currencyCode: currencyCode, showsPlus: true)
        return SpendingEntryRowModel(
            id: entry.id,
            title: title,
            subtitle: subtitle,
            amountText: amountText,
            amountTone: entry.amount > 0 ? .negative : entry.amount < 0 ? .positive : .neutral,
            accessibilityLabel: [title, subtitle, amountText].joined(separator: ", "),
        )
    }
}

import Foundation
import LittleOrbitDomain
import Observation

/// One row of the spending report, a category or a payee, ready for the list and VoiceOver.
public struct SpendingRowModel: Identifiable, Equatable, Sendable {
    /// The category's or payee's ID; `nil` for Uncategorised or No Payee.
    public var rowID: UUID?
    /// “Rent”, “Food & Dining › Groceries” or “Uncategorised”; or “Sunrise Apartments” or “No Payee”.
    public var name: String
    /// The category's icon and colour. `nil` for a payee row, which has no icon (#184 slice 4).
    public var symbolName: String?
    public var hue: CategoryHue?
    public var amountText: String
    /// “16.9%”, or `nil` when the total isn't above 0.
    public var shareText: String?
    /// “6 transactions”.
    public var countText: String
    /// “6”: the Mac table's Transactions column.
    public var countNumberText: String
    /// The bar's length as a fraction of the largest row, from 0 to 1. `nil` when the row is 0 or below (a
    /// refund-only row): it shows no bar, never a negative one.
    public var barFraction: Double?
    public var amountTone: AmountTone
    /// “Groceries, ₹12,450.50, Indian rupees, 16.9%, 6 transactions”: the row read as one line of a data table.
    public var accessibilityLabel: String

    public var id: UUID? { rowID }
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

/// “What do I spend my money on?” (#27, #184), or grouped by payee “Where do I spend the most?” (#184 slice 4),
/// for iOS and macOS. It depends only on `LoadSpendingReportUseCase`,
/// and every read is async, so the report is built off the main actor (Tech Architect's NB1 on #185).
@MainActor
@Observable
public final class SpendingReportViewModel {
    /// Whether the rows are categories or payees. Fixed for the screen.
    public let grouping: ReportGrouping
    /// The period shown: a preset, moved by ‹ ›, or a custom range. Change it with `select(_:)`.
    public internal(set) var selection: ReportSelection = .default
    /// The accounts counted: all of them, hidden ones too, until some are unticked (D417).
    public internal(set) var accountFilter: ReportAccountFilter = .all

    public private(set) var rows: [SpendingRowModel] = []
    /// The ranked bar chart above the rows (#184 slice 3): the 5 largest, then Other when it combines 2 or more.
    public private(set) var chartBars: [SpendingChartBar] = []
    public private(set) var totalText = ""
    public private(set) var totalCaption = ""
    public private(set) var periodTitle = ""
    public private(set) var currencies: [String] = []
    /// The currency shown: one at a time, never added together (D17).
    public private(set) var currencyCode = ""
    /// The account filter's list: every account in the shown currency, hidden ones included (D417).
    public private(set) var accounts: [ReportAccountOption] = []
    public private(set) var loadFailed = false
    /// True until the first load.
    public private(set) var isLoading = true
    /// Goes up on every load, whether or not the rows changed (Tech Architect's NB9 on #185). An open drill-down
    /// follows the store itself (`SpendingDrillDownModel.refresh(at:)`).
    public private(set) var revision = 0

    /// The shared store's revision the last `load(at:)` read, so a change is read once, whether the report or
    /// its open drill-down hears it first.
    @ObservationIgnored private var storeRevision: Int?
    @ObservationIgnored private var report: SpendingReport?
    @ObservationIgnored var requestedCurrency: String?
    /// Counts loads, so only the latest one started is shown when two overlap.
    @ObservationIgnored private var loadCount = 0
    @ObservationIgnored private let useCase: any LoadSpendingReportUseCase
    @ObservationIgnored let locale: Locale
    @ObservationIgnored let formatter: MoneyFormatter
    @ObservationIgnored let text: TransactionText
    @ObservationIgnored let timeZone: TimeZone
    @ObservationIgnored let now: () -> Date

    public init(
        useCase: any LoadSpendingReportUseCase,
        grouping: ReportGrouping = .category,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.useCase = useCase
        self.grouping = grouping
        self.locale = locale
        self.formatter = MoneyFormatter(locale: locale)
        self.text = TransactionText(locale: locale)
        self.timeZone = timeZone
        self.now = now
    }

    /// Shows `code` and keeps it while the period changes, as long as the period has spending in it.
    /// A new currency ticks every account again, since the list shows only that currency's accounts (UI Designer's
    /// slice 1 spec).
    public func selectCurrency(_ code: String) async {
        if code != currencyCode {
            accountFilter = .all
        }
        requestedCurrency = code
        await load()
    }

    /// Shows `period` from today, then reloads.
    public func select(_ period: ReportPeriod) async {
        await select(.preset(period))
    }

    /// Shows `selection`, then reloads.
    public func select(_ selection: ReportSelection) async {
        guard selection != self.selection else {
            return
        }
        self.selection = selection
        await load()
    }

    /// The preset the period picker shows; `nil` for a custom range.
    public var period: ReportPeriod? { selection.preset }

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

    var today: CalendarDay { TransactionTiming.today(now(), timeZone: timeZone) }

    /// What the next load reads.
    var query: SpendingReportQuery {
        SpendingReportQuery(
            range: selection.range(today: today),
            currencyCode: requestedCurrency,
            accounts: accountFilter,
            grouping: grouping,
        )
    }

    /// Reads the report again. A load that's overtaken by a newer one, or cancelled, changes nothing.
    public func load() async {
        loadCount += 1
        let current = loadCount
        let query = query
        do {
            let report = try await useCase.spendingReport(query)
            guard current == loadCount else {
                return
            }
            self.report = report
            loadFailed = false
            apply(report)
        } catch is CancellationError {
            return
        } catch {
            guard current == loadCount else {
                return
            }
            report = nil
            loadFailed = true
            rows = []
            chartBars = []
            totalText = ""
            totalCaption = ""
            currencies = []
            accounts = []
            periodTitle = title(of: query.range)
        }
        isLoading = false
        revision += 1
    }

    /// Loads again after a change to the shared store at `storeRevision`, from any window, unless that change has
    /// already been read.
    public func load(at storeRevision: Int) async {
        guard storeRevision != self.storeRevision else {
            return
        }
        self.storeRevision = storeRevision
        await load()
    }

    /// A drill-down for `row`, kept current while it's open.
    public func makeDrillDown(for row: SpendingRowModel) -> SpendingDrillDownModel {
        SpendingDrillDownModel(report: self, row: row)
    }

    /// The transactions behind `row`, read when its drill-down opens and again after each load. Its title is the
    /// row's current name, in case the category was renamed, and its share is the current one. `nil` if they can't
    /// be read.
    public func drillDown(for row: SpendingRowModel) async -> SpendingDrillDown? {
        guard let report else {
            return nil
        }
        let query = SpendingReportQuery(
            range: report.range,
            currencyCode: report.currencyCode,
            accounts: accountFilter,
            grouping: grouping,
        )
        guard let entries = try? await useCase.spendingEntries(query, categoryID: row.rowID) else {
            return nil
        }
        let today = today
        let total = entries.reduce(Decimal(0)) { $0 + $1.amount }
        // The report's current row, for its name and share. Gone once its last transaction is: no share then, so
        // the header is the period and currency only, as for any row without a share.
        let current = rows.first { $0.rowID == row.rowID }
        return SpendingDrillDown(
            title: (current ?? row).name,
            amountText: formatter.string(total, currencyCode: report.currencyCode),
            caption: ReportText.drillDownCaption(
                share: current?.shareText,
                period: title(of: report.range),
                accounts: accountsText(report.accounts),
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
        totalCaption = ReportText.spentCaption(
            period: periodTitle,
            accounts: accountsText(report.accounts),
            currencyCode: report.currencyCode,
        )
        accounts = report.accounts
        let largest = report.rows.map(\.amount).max() ?? 0
        rows = report.rows.map { row(for: $0, largest: largest, currencyCode: report.currencyCode) }
        chartBars = chartBars(for: report)
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
        let isCategory = grouping == .category
        return SpendingRowModel(
            rowID: row.id,
            name: name,
            symbolName: isCategory ? row.category.map(CategoryAppearance.symbol(of:)) ?? "questionmark" : nil,
            hue: isCategory ? row.category.map(CategoryAppearance.hue(of:)) ?? .gray : nil,
            amountText: amountText,
            shareText: shareText,
            countText: countText,
            countNumberText: row.transactionCount.formatted(.number.locale(locale)),
            barFraction: barFraction,
            amountTone: row.amount < 0 ? .negative : .neutral,
            accessibilityLabel: spoken.joined(separator: ", "),
        )
    }

    /// 169 tenths is “16.9%” in the view model's locale. A negative share takes the locale's own minus sign
    /// and its place from the format style, rather than one added in front (Tech Architect's NB8 on #185).
    func shareString(_ tenths: Int) -> String {
        (Decimal(tenths) / 1000)
            .formatted(.percent.precision(.fractionLength(1)).sign(strategy: .automatic).locale(locale))
    }

    /// “October 2026” for a month, “Oct – Dec 2026” for a quarter, “2026” for a year, and “15 Sep – 14 Oct 2026” for
    /// any other range, in the view model's locale, from the system formatters (UI Designer's slice 1 spec).
    func title(of range: ReportDayRange) -> String {
        switch range.shape {
        case .month:
            text.format(range.start, template: "MMMMyyyy")
        case .year:
            text.format(range.start, template: "yyyy")
        case .quarter:
            interval(range, days: false)
        case .days:
            interval(range, days: true)
        }
    }

    /// The system's interval format, as DateIntervalFormatter's MMMyyyy (or dMMMyyyy) template gives it: “Oct – Dec
    /// 2026”, “15 Sep – 14 Oct 2026”.
    private func interval(_ range: ReportDayRange, days: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        var style = Date.IntervalFormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
        if days {
            style = style.day()
        }
        style = style.month(.abbreviated).year()
        let start = TransactionCalendar.noon(on: range.start, timeZoneID: timeZone.identifier) ?? now()
        let end = TransactionCalendar.noon(on: range.end, timeZoneID: timeZone.identifier) ?? now()
        return style.format(start..<max(start, end))
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

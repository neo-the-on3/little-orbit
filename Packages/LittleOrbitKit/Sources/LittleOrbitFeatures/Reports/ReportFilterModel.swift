import Foundation
import LittleOrbitDomain
import Observation

/// The period, currency and account controls every report screen shares (#184): the preset picker with
/// Custom…, ‹ › stepping, the account filter and Try Again. The spending, payee and income reports and income
/// vs expenses (slice 5) all conform, so the controls are built once.
@MainActor
public protocol ReportFilterModel: AnyObject, Observable {
    /// The period shown: a preset, moved by ‹ ›, or a custom range.
    var selection: ReportSelection { get }
    /// The accounts counted: all of them, hidden ones too, until some are unticked (D417).
    var accountFilter: ReportAccountFilter { get }
    /// The account filter's list: every account in the shown currency, hidden ones included (D417).
    var accounts: [ReportAccountOption] { get }
    var currencies: [String] { get }
    /// The currency shown: one at a time, never added together (D17).
    var currencyCode: String { get }
    var periodTitle: String { get }
    /// The period picker's presets.
    var periods: [ReportPeriod] { get }
    var locale: Locale { get }
    var timeZone: TimeZone { get }
    var now: () -> Date { get }

    /// Shows `selection`, then reloads.
    func select(_ selection: ReportSelection) async
    /// Shows `code` and keeps it while the report is open, as long as the period has it.
    func selectCurrency(_ code: String) async
    /// Counts the accounts `filter` ticks, then reloads.
    func setAccountFilter(_ filter: ReportAccountFilter) async
    /// Reads the report again.
    func load() async
}

/// The shared controls' behaviour and wording.
extension ReportFilterModel {
    /// Today in the report's time zone.
    public var today: CalendarDay { TransactionTiming.today(now(), timeZone: timeZone) }

    // MARK: - Period

    /// Shows `period` from today, then reloads.
    public func select(_ period: ReportPeriod) async {
        await select(.preset(period))
    }

    /// The preset the period picker shows; `nil` for a custom range.
    public var period: ReportPeriod? { selection.preset }

    public func periodName(_ period: ReportPeriod) -> String {
        ReportText.periodName(period)
    }

    /// The picker only shows when the period has more than one currency.
    public var showsCurrencyPicker: Bool { currencies.count > 1 }

    // MARK: - ‹ › stepping

    /// One whole period back (‹, −1) or on (›, +1): a month, quarter or year. Nothing for a custom range.
    public func step(by steps: Int) async {
        guard canStep else {
            return
        }
        await select(selection.stepped(by: steps))
    }

    /// ‹ › and ⌘← ⌘→ are disabled for a custom range (UI Designer's slice 1 spec).
    public var canStep: Bool { selection.canStep }

    /// A preset moved by ‹ or ›, so the period menu shows the stepped period's title as its own choice, with the
    /// presets still below it (UI Designer's B2 on #307). Picking a preset goes back to its offset 0.
    public var isStepped: Bool {
        if case .preset(_, let offset) = selection {
            return offset != 0
        }
        return false
    }

    public var previousPeriodLabel: String { ReportText.previousPeriod }
    public var nextPeriodLabel: String { ReportText.nextPeriod }

    // MARK: - Custom range

    /// A custom range is shown, so the period picker reads Custom… and the two day pickers show.
    public var isCustomRange: Bool { selection.preset == nil }

    public var customRangeName: String { ReportText.customRange }
    public var customStartLabel: String { ReportText.customStart }
    public var customEndLabel: String { ReportText.customEnd }
    public var bothDatesIncluded: String { ReportText.bothDatesIncluded }

    /// Switches to a custom range that starts as the period shown, so nothing changes until a day is picked.
    public func selectCustomRange() async {
        await select(.custom(selection.range(today: today)))
    }

    /// The shown range's first day, at noon in the report's time zone, for a date picker.
    public var customStart: Date { noon(on: selection.range(today: today).start) }
    /// The shown range's last day, at noon in the report's time zone, for a date picker.
    public var customEnd: Date { noon(on: selection.range(today: today).end) }

    /// Shows the days from `start` through `end`, both included, as days in the report's time zone. An end
    /// before the start is read start first.
    public func selectCustomRange(from start: Date, to end: Date) async {
        let range = ReportDayRange(start: day(of: start), end: day(of: end))
        await select(.custom(ReportSelection.custom(range).range(today: today)))
    }

    // MARK: - Accounts

    public var accountsTitle: String { ReportText.accountsTitle }
    public var hiddenAccountNote: String { ReportText.hiddenAccount }

    /// The Accounts row's value: “All”, or “2 of 3”.
    public var accountsValue: String {
        ReportText.accountsValue(accounts.filter(\.isIncluded).count, total: accounts.count)
    }

    /// “Only INR accounts are listed because the report shows INR.”
    public var accountsFooter: String { ReportText.accountsFooter(currencyCode: currencyCode) }

    /// The last ticked account can't be unticked (UI Designer's slice 1 spec): its row is disabled. It reads the
    /// filter itself, not the last loaded list, so two quick unticks can't both go through before the reload
    /// (Tech Architect's N1 on #307).
    public func canUntick(_ accountID: UUID) -> Bool {
        accounts.contains { $0.id != accountID && accountFilter.includes($0.id) }
    }

    /// Ticks or unticks an account, then reloads. Hidden accounts start ticked like the others (D417). Unticking
    /// the last ticked account does nothing.
    public func setAccount(_ accountID: UUID, included: Bool) async {
        if !included, !canUntick(accountID) {
            return
        }
        var filter = accountFilter
        filter.set(included, for: accountID)
        guard filter != accountFilter else {
            return
        }
        await setAccountFilter(filter)
    }

    /// “all accounts”, or “2 of 3 accounts”: how many of the shown currency's accounts count.
    func accountsText(_ options: [ReportAccountOption]) -> String {
        let included = options.filter(\.isIncluded).count
        guard included < options.count else {
            return ReportText.allAccounts
        }
        return ReportText.accountsOf(included, total: options.count)
    }

    // MARK: - Try Again

    public var tryAgainButton: String { ReportText.tryAgainButton }
    public var loadFailedTitle: String { ReportText.loadFailedTitle }
    public var loadFailedMessage: String { ReportText.tryAgain }

    /// Try Again after a failed read (D318.5).
    public func retry() async {
        await load()
    }

    // MARK: - Days and dates

    /// “October 2026” for a month, “Oct – Dec 2026” for a quarter, “2026” for a year, “May – Oct 2026” for other
    /// whole months, and “15 Sep – 14 Oct 2026” for any other range, in the view model's locale, from the system formatters (UI Designer's slice 1 spec).
    public func title(of range: ReportDayRange) -> String {
        switch range.shape {
        case .month:
            TransactionText(locale: locale).format(range.start, template: "MMMMyyyy")
        case .year:
            TransactionText(locale: locale).format(range.start, template: "yyyy")
        case .quarter, .months:
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

    private func noon(on day: CalendarDay) -> Date {
        TransactionCalendar.noon(on: day, timeZoneID: timeZone.identifier) ?? now()
    }

    private func day(of date: Date) -> CalendarDay {
        TransactionCalendar.ownDay(of: date, timeZoneID: timeZone.identifier)
    }
}

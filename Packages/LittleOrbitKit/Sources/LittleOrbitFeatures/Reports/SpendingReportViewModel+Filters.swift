import Foundation
import LittleOrbitDomain

/// The spending report's period stepping, custom range, account filter and Try Again (#184).
extension SpendingReportViewModel {
    // MARK: - ‹ › stepping

    /// One whole period back (‹, −1) or on (›, +1): a month, quarter or year, or a custom range's own length.
    public func step(by steps: Int) async {
        await select(selection.stepped(by: steps, today: today))
    }

    public var previousPeriodLabel: String { ReportText.previousPeriod }
    public var nextPeriodLabel: String { ReportText.nextPeriod }

    // MARK: - Custom range

    /// A custom range is shown, so the period picker reads Custom Range and the two day pickers show.
    public var isCustomRange: Bool { selection.preset == nil }

    public var customRangeName: String { ReportText.customRange }
    public var customStartLabel: String { ReportText.customStart }
    public var customEndLabel: String { ReportText.customEnd }

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

    /// Ticks or unticks an account, then reloads. Hidden accounts start ticked like the others (D417).
    public func setAccount(_ accountID: UUID, included: Bool) async {
        var filter = accountFilter
        filter.set(included, for: accountID)
        guard filter != accountFilter else {
            return
        }
        accountFilter = filter
        await load()
    }

    /// “all accounts”, the one account's name, or “2 accounts”: which of the shown currency's accounts count.
    func accountsText(_ options: [ReportAccountOption]) -> String {
        let included = options.filter(\.isIncluded)
        if included.count == options.count {
            return ReportText.allAccounts
        }
        if included.count == 1, let only = included.first {
            return only.account.name
        }
        return ReportText.accountCount(included.count)
    }

    // MARK: - Try Again

    public var tryAgainButton: String { ReportText.tryAgainButton }

    /// Try Again after a failed read (D318.5).
    public func retry() async {
        await load()
    }

    // MARK: - Days and dates

    private func noon(on day: CalendarDay) -> Date {
        TransactionCalendar.noon(on: day, timeZoneID: timeZone.identifier) ?? now()
    }

    private func day(of date: Date) -> CalendarDay {
        TransactionCalendar.ownDay(of: date, timeZoneID: timeZone.identifier)
    }
}

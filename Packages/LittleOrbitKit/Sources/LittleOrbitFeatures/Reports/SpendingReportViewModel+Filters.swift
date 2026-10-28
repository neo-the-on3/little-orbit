import Foundation
import LittleOrbitDomain

/// The spending report's period stepping, custom range, account filter and Try Again (#184).
extension SpendingReportViewModel {
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

    /// The last ticked account can't be unticked (UI Designer's slice 1 spec): its row is disabled.
    public func canUntick(_ accountID: UUID) -> Bool {
        accounts.contains { $0.id != accountID && $0.isIncluded }
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
        accountFilter = filter
        await load()
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

import Foundation
import LittleOrbitDomain

/// The header, facts and hints of the budget detail for the period on show (#25 detail frames, D307.2, D307.3,
/// D308). Built from `BudgetDetail` by `BudgetDetailViewModel`; the view only lays it out.
public struct BudgetDetailHeader: Equatable, Sendable {
    /// One line under the header: a label on the left and a value on the right.
    public struct Fact: Identifiable, Equatable, Sendable {
        public var id: String { label }
        public var label: String
        public var value: String
        public var tone: AmountTone
    }

    /// “1–31 Oct 2026”, the same range style as the form's Next periods (UI Designer on #176).
    public var periodText: String
    public var isCurrentPeriod: Bool
    public var canShowPrevious: Bool
    public var canShowNext: Bool
    /// The status and colour, shared with the list rows.
    public var status: BudgetRow.Status
    /// “₹6,050.00 left”, “₹1,200.00 over”, “₹1,500.00 unused”, “Nothing spent yet” or “Starts 1 Nov”.
    public var headline: String
    /// The symbol before the headline: a warning near the limit, an alert when overspent.
    public var headlineSymbol: String?
    /// “of ₹9,500.00 available”, “Overspent · limit ₹5,000.00”, “₹0.00 spent · −₹500.00 available” or
    /// “Ended 30 Sep · of ₹7,000.00”.
    public var subline: String
    /// 0 to 1, full when overspent (S68). `nil` before the start date: nothing to measure (D308 amendment).
    public var progress: Double?
    /// “Spent ₹3,450.00”.
    public var spentText: String
    /// “12 days left · resets 1 Nov”, “Last day · resets 1 Nov”, the repeat before the start date, or empty on a
    /// past period.
    public var timingText: String
    public var facts: [Fact]
    /// The other-currency hint (D307.3, D311.1) and, on a past period, the limit it had (D311.3).
    public var hints: [String]
    public var accessibilityLabel: String
}

/// One transaction row of the budget detail (#25 frames; D233, D237, S72–S75).
public struct BudgetTransactionRow: Identifiable, Equatable, Sendable {
    public var id: String
    /// The payee, the description, or “Expense”; a refund reads “Refund · ‹payee›” (D233).
    public var title: String
    /// “Restaurants · Everyday Savings”, or “Split · Household · Everyday Savings” for a split line.
    public var subtitle: String
    /// “−₹250.00”, or “+₹300.00” for a refund (D173.2).
    public var amountText: String
    public var tone: AmountTone
    /// “20 Oct”, or “3 Jan 2027” in another year.
    public var dateText: String
    public var symbolName: String
    public var accessibilityLabel: String
}

/// Formats period ranges and days for the detail, as calendar days so no time zone moves them.
struct BudgetDetailDates {
    private let range: DateIntervalFormatter
    private let full: DateFormatter
    private let month: DateFormatter
    let short: BudgetStartDates

    init(locale: Locale) {
        range = DateIntervalFormatter()
        range.locale = locale
        range.calendar = BudgetDays.calendar
        range.timeZone = BudgetDays.calendar.timeZone
        range.dateTemplate = "dMMMy"
        full = DateFormatter()
        full.locale = locale
        full.calendar = BudgetDays.calendar
        full.timeZone = BudgetDays.calendar.timeZone
        full.setLocalizedDateFormatFromTemplate("yMMMd")
        month = DateFormatter()
        month.locale = locale
        month.calendar = BudgetDays.calendar
        month.timeZone = BudgetDays.calendar.timeZone
        month.setLocalizedDateFormatFromTemplate("yMMM")
        short = BudgetStartDates(locale: locale)
    }

    /// “1–31 Oct 2026”, as the platform formats the range in the user's language, unchanged (#177 review NB1).
    func range(_ period: BudgetPeriod) -> String {
        range.string(from: BudgetDays.date(period.start), to: BudgetDays.date(period.end))
    }

    /// “1 Oct 2026”.
    func full(_ day: CalendarDay) -> String {
        full.string(from: BudgetDays.date(day))
    }

    /// “Oct 2026”.
    func month(_ day: CalendarDay) -> String {
        month.string(from: BudgetDays.date(day))
    }
}

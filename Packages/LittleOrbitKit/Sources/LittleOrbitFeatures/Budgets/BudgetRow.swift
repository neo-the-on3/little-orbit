import Foundation
import LittleOrbitDomain

/// One row of the iOS budget list (#25): the name and status, a bar, spent of what's available, and the
/// repeat with the days left in the current period. Copy follows D308 and its amendments.
public struct BudgetRow: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Before the start date: one status, no symbol, no bar (D308 amendment).
        case notStarted
        case nothingSpent
        case onTrack
        case nearLimit
        case overspent
        /// No categories left: only the name and "No categories" (D307.5, D308 amendment 2).
        case noCategories
    }

    public var id: UUID
    public var name: String
    public var status: Status
    /// "₹6,050.00 left", "₹1,200.00 over", "Nothing spent yet", "Starts tomorrow", "Starts 1 Nov" or
    /// "No categories".
    public var statusText: String
    /// The SF Symbol before the status: a warning near the limit, an alert when overspent.
    public var statusSymbol: String?
    /// The share of what's available that's spent, 0 to 1. An overspent bar stops at full (S68). `nil` hides
    /// the bar: before the start date and with no categories.
    public var progress: Double?
    /// "₹3,450.00 of ₹9,500.00", with " · 94%" near the limit, or "₹0.00 spent · −₹500.00 available" below 0
    /// available. `nil` with no categories.
    public var amountsText: String?
    /// "Monthly · 12 days left" or "Monthly · Last day", or just the repeat before the start date. `nil` with no
    /// categories.
    public var timingText: String?
    /// The whole row for VoiceOver, with the symbol's meaning in words.
    public var accessibilityLabel: String
    /// Whether the current period has one before it, for the Mac's Show Previous Period from the list, which is
    /// dimmed in a budget's first period (UI Designer's #180 B1). Always false with no categories.
    public var hasPreviousPeriod: Bool

    init(_ summary: BudgetSummary, today: CalendarDay, money: MoneyFormatter, dates: BudgetStartDates) {
        let figures = summary.current.figures
        let currency = summary.budget.currencyCode
        let status = Self.status(of: summary)
        let remaining = money.string(figures.remaining.magnitude, currencyCode: currency)
        let spent = money.string(figures.spent, currencyCode: currency)
        let available = money.string(figures.available, currencyCode: currency)
        let recurrence = BudgetText.recurrence(summary.budget.recurrence)
        let days = BudgetText.daysLeft(summary.daysUntilNextPeriod)

        id = summary.id
        name = summary.budget.name
        self.status = status
        statusSymbol = Self.symbol(for: status)
        hasPreviousPeriod = status != .noCategories && summary.current.period.index > 0

        switch status {
        case .noCategories:
            statusText = BudgetText.noCategories
            progress = nil
            amountsText = nil
            timingText = nil
            accessibilityLabel = [name, statusText].joined(separator: ", ")
        case .notStarted:
            statusText =
                summary.daysUntilNextPeriod == 1
                ? BudgetText.startsTomorrow
                : BudgetText.starts(dates.string(summary.budget.startDay, today: today))
            progress = nil
            amountsText = BudgetText.spentOf(spent, available)
            timingText = recurrence
            accessibilityLabel = [name, statusText, BudgetText.spentOf(spent, available), recurrence]
                .joined(separator: ", ")
        case .nothingSpent, .onTrack, .nearLimit, .overspent:
            statusText = status == .overspent ? BudgetText.over(remaining) : Self.leftText(status, remaining)
            // Overspent is always a full bar, also below 0 available with nothing spent (D307.2).
            progress = status == .overspent ? 1 : Self.progress(of: figures)
            let percent = Self.percent(of: figures)
            // Below 0 available, spent and available are named, since "of" a negative amount reads wrong
            // (D307 amendment).
            let spoken =
                figures.available < 0
                ? [BudgetText.spent(spent), BudgetText.available(available)]
                : [BudgetText.spentOf(spent, available)]
            if figures.available < 0 {
                amountsText = BudgetText.pair(spoken[0], spoken[1])
            } else if status == .nearLimit, let percent {
                amountsText = BudgetText.spentOf(spent, available, percent: percent)
            } else {
                amountsText = BudgetText.spentOf(spent, available)
            }
            timingText = BudgetText.pair(recurrence, days)
            // The percentage is read after the amounts whenever more than 0 is available (D308.6).
            let percentText = percent.map { [BudgetText.percent($0)] } ?? []
            accessibilityLabel =
                ([name] + Self.spokenStatus(status, statusText) + spoken + percentText
                + [recurrence, days])
                .joined(separator: ", ")
        }
    }

    private static func leftText(_ status: Status, _ remaining: String) -> String {
        status == .nothingSpent ? BudgetText.nothingSpent : BudgetText.left(remaining)
    }

    private static func symbol(for status: Status) -> String? {
        switch status {
        case .nearLimit: "exclamationmark.triangle.fill"
        case .overspent: "exclamationmark.circle"
        case .notStarted, .nothingSpent, .onTrack, .noCategories: nil
        }
    }

    /// The status as VoiceOver reads it: the symbol's meaning in words, then the status text.
    private static func spokenStatus(_ status: Status, _ text: String) -> [String] {
        switch status {
        case .notStarted, .nothingSpent, .onTrack, .noCategories: [text]
        case .nearLimit: [BudgetText.nearLimit, text]
        case .overspent: [BudgetText.overspent, text]
        }
    }

    private static func status(of summary: BudgetSummary) -> Status {
        if summary.hasNoCategories {
            return .noCategories
        }
        switch summary.current.state {
        case .notStarted: return .notStarted
        case .overspent: return .overspent
        case .nearLimit: return .nearLimit
        case .onTrack: return summary.current.figures.netSpending == 0 ? .nothingSpent : .onTrack
        }
    }

    private static func progress(of figures: BudgetFigures) -> Double {
        guard figures.available > 0 else {
            return 0
        }
        let share = Double(truncating: (figures.spent / figures.available) as NSDecimalNumber)
        return min(1, max(0, share))
    }

    /// The share spent as a whole percentage, rounded half up: 11,250 of 12,000 is 94%. While spent is below
    /// what's available it's capped at 99%, so "100%" only shows at the limit (D308.5). `nil` unless more than 0
    /// is available.
    static func percent(of figures: BudgetFigures) -> Int? {
        guard figures.available > 0 else {
            return nil
        }
        var share = figures.spent * 100 / figures.available
        var rounded = Decimal()
        NSDecimalRound(&rounded, &share, 0, .plain)
        let percent = Int(truncating: rounded as NSDecimalNumber)
        return figures.spent < figures.available ? min(percent, 99) : percent
    }
}

/// A budget's start date for "Starts %@": the system medium date, without the year in the current year, in
/// the locale's own order (D308 amendment). Days are calendar days, so no time zone moves them.
struct BudgetStartDates {
    private let sameYear: DateFormatter
    private let otherYear: DateFormatter
    private let calendar: Calendar

    init(locale: Locale) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        self.calendar = calendar
        func formatter(_ template: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
        sameYear = formatter("MMMd")
        otherYear = formatter("yMMMd")
    }

    func string(_ day: CalendarDay, today: CalendarDay) -> String {
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        guard let date = calendar.date(from: components) else {
            return ""
        }
        return (day.year == today.year ? sameYear : otherYear).string(from: date)
    }
}

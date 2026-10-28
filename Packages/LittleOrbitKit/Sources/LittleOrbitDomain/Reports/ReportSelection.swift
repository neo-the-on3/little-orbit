import Foundation

/// What a report covers (#184): a preset period, moved back or on by ‹ › some whole periods, or a custom range
/// with both end days included. A custom range doesn't step: ‹ › are disabled for it (UI Designer's slice 1 spec).
public enum ReportSelection: Hashable, Sendable {
    /// `offset` whole periods from `period`: This Month moved on 1 is next month.
    case preset(ReportPeriod, offset: Int = 0)
    /// Both end days included.
    case custom(ReportDayRange)

    public static let `default` = ReportSelection.preset(.thisMonth)

    /// The days covered for `today`. A custom range given end first is read start first.
    public func range(today: CalendarDay) -> ReportDayRange {
        switch self {
        case .preset(let period, let offset):
            period.range(today: today).stepped(by: offset)
        case .custom(let range):
            range.start <= range.end ? range : ReportDayRange(start: range.end, end: range.start)
        }
    }

    /// The same preset `steps` periods on (back when negative). A custom range comes back unchanged.
    public func stepped(by steps: Int) -> ReportSelection {
        switch self {
        case .preset(let period, let offset):
            .preset(period, offset: offset + steps)
        case .custom:
            self
        }
    }

    /// Whether ‹ › step it: presets only.
    public var canStep: Bool { preset != nil }

    /// The preset it started from, or `nil` for a custom range.
    public var preset: ReportPeriod? {
        if case .preset(let period, _) = self {
            return period
        }
        return nil
    }
}

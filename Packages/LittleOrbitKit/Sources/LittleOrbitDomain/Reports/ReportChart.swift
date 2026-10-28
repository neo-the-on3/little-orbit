import Foundation

/// One bar of a report's ranked bar chart (#184 slice 3): a row, or “Other” combining the smaller rows.
public struct ReportChartBar: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The row at this index of the report's rows.
        case row(Int)
        /// The positive rows after the largest ones, this many of them.
        case other(count: Int)
    }

    public var kind: Kind
    public var amount: Decimal
    /// Tenths of a percent, from the rows' own largest-remainder shares, so Other's share is the sum of the
    /// shares it combines and every bar's share matches the list. `nil` when the rows have none.
    public var shareTenths: Int?

    public init(kind: Kind, amount: Decimal, shareTenths: Int?) {
        self.kind = kind
        self.amount = amount
        self.shareTenths = shareTenths
    }
}

/// The ranked bars of a report (UI Designer's slice 3 spec): the largest positive rows, then “Other” combining
/// the rest, but only when it combines 2 or more, so with one row over the limit that row gets its own bar.
/// Rows at 0 or below get no bar (D316 amendment); they stay in the list.
public enum ReportChart {
    /// How many rows get a bar of their own before “Other”.
    public static let namedBars = 5

    /// `amounts` and `shares` are the report's rows in its order, largest first.
    public static func bars(amounts: [Decimal], shares: [Int?], named: Int = namedBars) -> [ReportChartBar] {
        let positive = amounts.indices.filter { amounts[$0] > 0 }.sorted { amounts[$0] > amounts[$1] }
        let share = { (index: Int) in index < shares.count ? shares[index] : nil }
        guard positive.count > named + 1 else {
            return positive.map { ReportChartBar(kind: .row($0), amount: amounts[$0], shareTenths: share($0)) }
        }
        let shown = positive.prefix(named)
        let rest = positive.dropFirst(named)
        let restShares = rest.map(share)
        let otherShare = restShares.contains(nil) ? nil : restShares.compactMap(\.self).reduce(0, +)
        let other = ReportChartBar(
            kind: .other(count: rest.count),
            amount: rest.reduce(Decimal(0)) { $0 + amounts[$1] },
            shareTenths: otherShare,
        )
        return shown.map { ReportChartBar(kind: .row($0), amount: amounts[$0], shareTenths: share($0)) } + [other]
    }
}

extension SpendingReport {
    /// The chart's bars for this report's rows.
    public var chartBars: [ReportChartBar] {
        ReportChart.bars(amounts: rows.map(\.amount), shares: rows.map(\.shareTenths))
    }
}

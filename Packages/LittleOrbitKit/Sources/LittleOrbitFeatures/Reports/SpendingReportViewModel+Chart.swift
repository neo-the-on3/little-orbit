import Foundation
import LittleOrbitDomain

/// One bar of the spending chart (#184 slice 3), ready for Swift Charts, VoiceOver and the audio graph.
public struct SpendingChartBar: Identifiable, Equatable, Sendable {
    /// The row's category ID, “uncategorised”, or “other”.
    public var id: String
    /// The bar's axis label: “Rent”, or “Other · 2 categories”.
    public var name: String
    /// The bar's length, in the report's currency.
    public var amount: Double
    /// “₹12,450.50”, for VoiceOver and the audio graph.
    public var amountText: String
    /// “₹12K”: the annotation at the bar's end. The list below keeps the full amount.
    public var compactAmountText: String
    /// “16.9%”, or `nil` when the total isn't above 0.
    public var shareText: String?
    /// 0.169 for 16.9%, from the same tenths as `shareText`, for the audio graph's Share axis.
    public var share: Double?
    /// The category's colour, or `nil` for Other, which is secondary.
    public var hue: CategoryHue?
    /// The row whose drill-down a tap opens, or `nil` for Other, which isn't tappable.
    public var row: SpendingRowModel?
    /// “Rent”, or “Other, 2 categories”: the bar's name in the audio graph. The bars themselves are hidden from
    /// VoiceOver (UI Designer's answer on #310).
    public var accessibilityLabel: String
    /// “₹12,450.50, 16.9%”: the bar's amount, then its share.
    public var accessibilityValue: String
}

/// One point of the chart's audio graph: a bar, named so no two points share a category. VoiceOver reads it as
/// its category, its amount from the Amount axis, then its share from the Share axis, each once.
public struct SpendingChartAudioPoint: Identifiable, Equatable, Sendable {
    /// The bar's ID.
    public var id: String
    /// “Rent”, “Other, 2 categories”, or “Uncategorised (2)” for the second bar named “Uncategorised”.
    public var category: String
    public var amount: Double
    /// 0.169 for 16.9%, or `nil` when the rows have no shares.
    public var share: Double?
}

extension SpendingReportViewModel {
    /// The audio graph's title: the report's question.
    public var chartTitle: String { ReportText.spendingQuestion }
    /// The audio graph's summary: the caption under the total.
    public var chartSummary: String { totalCaption }
    public var chartCategoryAxis: String { ReportText.categoryColumn }
    public var chartAmountAxis: String { ReportText.amountColumn }
    public var transactionsColumn: String { ReportText.transactionsColumn }
    public var shareColumn: String { ReportText.shareColumn }

    /// “₹12,450.50” for an audio graph value, in the shown currency.
    public func chartAmountText(_ amount: Double) -> String {
        formatter.string(Decimal(amount), currencyCode: currencyCode)
    }

    /// The bar with `id`, the value Swift Charts gives back for a tap or an axis label. Bars are keyed by their
    /// row's ID, never their name, since two rows can share a name (Tech Architect's n1 on #310).
    public func chartBar(id: String) -> SpendingChartBar? {
        chartBars.first { $0.id == id }
    }

    /// The row whose drill-down a tap on the bar with `id` opens, or `nil` for Other or no bar.
    public func chartRow(id: String) -> SpendingRowModel? {
        chartBar(id: id)?.row
    }

    /// The audio graph's points, one per bar in the chart's order. A name that more than one bar has gets its
    /// position among them after the first, as in “Uncategorised (2)”, because the audio graph's category axis
    /// tells points apart by their name alone.
    public var chartAudioPoints: [SpendingChartAudioPoint] {
        var seen: [String: Int] = [:]
        return chartBars.map { bar in
            let ordinal = (seen[bar.accessibilityLabel] ?? 0) + 1
            seen[bar.accessibilityLabel] = ordinal
            let category =
                ordinal == 1 ? bar.accessibilityLabel : ReportText.repeatedBarName(bar.accessibilityLabel, ordinal)
            return SpendingChartAudioPoint(
                id: bar.id,
                category: category,
                amount: bar.amount,
                share: bar.share,
            )
        }
    }

    func chartBars(for report: SpendingReport) -> [SpendingChartBar] {
        report.chartBars.map { bar in
            let amountText = formatter.string(bar.amount, currencyCode: report.currencyCode)
            let shareText = bar.shareTenths.map(shareString)
            let share = bar.shareTenths.map { Double($0) / 1000 }
            let value = [amountText, shareText].compactMap(\.self).joined(separator: ", ")
            let compact = bar.amount.formatted(
                .currency(code: report.currencyCode).notation(.compactName).locale(locale)
            )
            let amount = NSDecimalNumber(decimal: bar.amount).doubleValue
            switch bar.kind {
            case .row(let index):
                let row = rows[index]
                return SpendingChartBar(
                    id: row.categoryID?.uuidString ?? "uncategorised",
                    name: row.name,
                    amount: amount,
                    amountText: amountText,
                    compactAmountText: compact,
                    shareText: shareText,
                    share: share,
                    hue: row.hue,
                    row: row,
                    accessibilityLabel: row.name,
                    accessibilityValue: value,
                )
            case .other(let count):
                return SpendingChartBar(
                    id: "other",
                    name: ReportText.otherCategories(count),
                    amount: amount,
                    amountText: amountText,
                    compactAmountText: compact,
                    shareText: shareText,
                    share: share,
                    hue: nil,
                    row: nil,
                    accessibilityLabel: ReportText.otherCategoriesSpoken(count),
                    accessibilityValue: value,
                )
            }
        }
    }
}

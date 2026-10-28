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
    /// The category's colour, or `nil` for Other, which is secondary.
    public var hue: CategoryHue?
    /// The row whose drill-down a tap opens, or `nil` for Other, which isn't tappable.
    public var row: SpendingRowModel?
    /// “Rent”, or “Other, 2 categories”: the bar's name in the audio graph. The bars themselves are hidden from
    /// VoiceOver (UI Designer's answer on #310).
    public var accessibilityLabel: String
    /// “₹12,450.50, 16.9%”: the amount, then the share, read for the bar's point in the audio graph.
    public var accessibilityValue: String
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

    /// The bar whose drill-down a tap on `name` opens, or `nil` for Other or no bar.
    public func chartRow(named name: String) -> SpendingRowModel? {
        chartBars.first { $0.name == name }?.row
    }

    func chartBars(for report: SpendingReport) -> [SpendingChartBar] {
        report.chartBars.map { bar in
            let amountText = formatter.string(bar.amount, currencyCode: report.currencyCode)
            let shareText = bar.shareTenths.map(shareString)
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
                    hue: nil,
                    row: nil,
                    accessibilityLabel: ReportText.otherCategoriesSpoken(count),
                    accessibilityValue: value,
                )
            }
        }
    }
}

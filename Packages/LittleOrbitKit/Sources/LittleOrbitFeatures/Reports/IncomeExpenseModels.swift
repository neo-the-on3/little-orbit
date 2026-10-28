import Foundation
import LittleOrbitDomain

/// One figure of a report's header or the Reports list summary: “Earned ₹1,62,000.00” (#184 slice 5).
public struct ReportValueModel: Identifiable, Equatable, Sendable {
    /// “Earned”, “Spent” or “Left over”.
    public var label: String
    /// The full amount, one line, scaling down to fit. Left over is signed: “+₹88,251.50”.
    public var amountText: String
    public var amountTone: AmountTone
    /// “Spent, ₹73,748.50”: the figure as one VoiceOver element.
    public var accessibilityLabel: String

    public var id: String { label }
}

/// One month of income vs expenses, or the Mac table's Total row (#184 slice 5).
public struct IncomeExpenseRowModel: Identifiable, Equatable, Sendable {
    /// The month's first day, or “total”.
    public var id: String
    /// “Oct 2026”, or “Total”.
    public var title: String
    public var incomeText: String
    public var expensesText: String
    /// Signed: “+₹88,251.50”, “−₹20,000.00” or “₹0.00”.
    public var leftOverText: String
    public var leftOverTone: AmountTone
    /// “In ₹1,62,000.00 · Out ₹73,748.50”.
    public var subtitle: String
    /// “October 2026, left over ₹88,251.50, income ₹1,62,000.00, expenses ₹73,748.50”.
    public var accessibilityLabel: String
    /// The Mac table's last row, the sums of the months.
    public var isTotal: Bool
}

/// One bar of the income vs expenses chart: a month's income or its expenses (#184 slice 5).
public struct IncomeExpenseChartBar: Identifiable, Equatable, Sendable {
    public var id: String
    /// The month's first day at noon, for the chart's month axis.
    public var month: Date
    /// “October 2026”, for the audio graph.
    public var monthTitle: String
    /// “Income” or “Expenses”.
    public var series: String
    /// The bar's height: 0 for a month with nothing, never below 0.
    public var amount: Double
    /// “₹1,62,000.00”, for the audio graph. Expenses below 0 (refunds only) read signed.
    public var amountText: String
}

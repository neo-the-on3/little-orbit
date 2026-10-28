import Foundation

/// “How much do I earn compared to my expenses?” and the Reports list's summary (#184 slice 5, UI Designer's
/// spec, D420).
extension ReportText {
    static var incomeExpenseQuestion: String {
        FeatureText.string(
            "How much do I earn compared to my expenses?",
            comment:
                "The income-vs-expenses report’s title, a plain question: its row on Reports and its heading (D420).",
        )
    }

    static var incomeExpenseTitle: String {
        FeatureText.string(
            "Income vs Expenses",
            comment: "Navigation title of the income-vs-expenses report, also its Back button and Mac window title.",
        )
    }

    static var earned: String {
        FeatureText.string("Earned", comment: "Reports: the income figure’s label, as in “Earned ₹1,62,000.00”.")
    }

    static var spent: String {
        FeatureText.string("Spent", comment: "Reports: the spending figure’s label, as in “Spent ₹73,748.50”.")
    }

    static var leftOver: String {
        FeatureText.string("Left over", comment: "Reports: earned minus spent, as in “Left over +₹88,251.50”.")
    }

    /// “Spent, ₹73,748.50”: one figure as VoiceOver reads it.
    static func valueSpoken(_ label: String, _ amount: String) -> String {
        FeatureText.format("%1$@, %2$@", label, amount)
    }

    /// “In ₹1,62,000.00 · Out ₹73,748.50”: a month row's subtitle.
    static func inOut(income: String, expenses: String) -> String {
        FeatureText.format("In %1$@ · Out %2$@", income, expenses)
    }

    /// “October 2026, left over ₹88,251.50, income ₹1,62,000.00, expenses ₹73,748.50”: a month row for VoiceOver.
    static func monthSpoken(month: String, leftOver: String, income: String, expenses: String) -> String {
        FeatureText.format(
            "%1$@, left over %2$@, income %3$@, expenses %4$@",
            month,
            leftOver,
            income,
            expenses,
        )
    }

    static var incomeExpenseFooter: String {
        FeatureText.string(
            "Transfers between your own accounts aren’t counted. Refunds reduce expenses and are never income.",
            comment: "Income vs expenses: the footer under the month rows.",
        )
    }

    static var noIncomeOrExpensesTitle: String {
        FeatureText.string(
            "No Income or Expenses",
            comment: "Income vs expenses empty state title, when the whole range has no income and no expenses.",
        )
    }

    static var noIncomeOrExpensesMessage: String {
        FeatureText.string(
            "There’s nothing to compare in this period. Try another period.",
            comment: "Income vs expenses empty state message, under “No Income or Expenses”.",
        )
    }

    /// The chart's and the audio graph's income series.
    static var incomeSeries: String {
        FeatureText.string(
            key: "report.series.income",
            defaultValue: "Income",
            comment: "Income vs expenses chart: the income series, named in the legend and the audio graph.",
        )
    }

    /// The chart's and the audio graph's expenses series.
    static var expensesSeries: String {
        FeatureText.string(
            key: "report.series.expenses",
            defaultValue: "Expenses",
            comment: "Income vs expenses chart: the expenses series, named in the legend and the audio graph.",
        )
    }

    static var monthColumn: String {
        FeatureText.string(
            key: "report.column.month",
            defaultValue: "Month",
            comment: "Income vs expenses: the Mac table’s month column, and the audio graph’s month axis.",
        )
    }

    static var incomeColumn: String {
        FeatureText.string(
            key: "report.column.income",
            defaultValue: "Income",
            comment: "Income vs expenses: the Mac table’s income column.",
        )
    }

    static var expensesColumn: String {
        FeatureText.string(
            key: "report.column.expenses",
            defaultValue: "Expenses",
            comment: "Income vs expenses: the Mac table’s expenses column.",
        )
    }

    static var leftOverColumn: String {
        FeatureText.string(
            key: "report.column.leftOver",
            defaultValue: "Left over",
            comment: "Income vs expenses: the Mac table’s left-over column, income minus expenses.",
        )
    }

    /// The Mac table's last row, the sums of the months.
    static var totalRow: String {
        FeatureText.string("Total", comment: "Income vs expenses: the Mac table’s last row, the sums of the months.")
    }

    /// “Earned − spent, October 2026 · INR”: the Reports list summary's caption.
    static func summaryCaption(period: String, currencyCode: String) -> String {
        FeatureText.format("Earned − spent, %1$@ · %2$@", period, currencyCode)
    }

    /// The caption's scope: “May – Oct 2026 · all accounts · INR”.
    static func scope(period: String, accounts: String, currencyCode: String) -> String {
        FeatureText.format("%1$@ · %2$@ · %3$@", period, accounts, currencyCode)
    }
}

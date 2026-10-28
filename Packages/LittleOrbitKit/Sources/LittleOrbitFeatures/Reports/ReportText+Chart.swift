import Foundation

/// The spending chart's and Mac table’s wording (#184 slice 3, UI Designer's spec).
extension ReportText {
    /// “Other · 2 categories”: the chart's last bar, combining the smaller categories. Always 2 or more.
    static func otherCategories(_ count: Int) -> String {
        FeatureText.plural("Other · %lld categories", one: "Other · %lld category", count)
    }

    /// “Other, 2 categories”: how VoiceOver names the Other bar.
    static func otherCategoriesSpoken(_ count: Int) -> String {
        FeatureText.plural("Other, %lld categories", one: "Other, %lld category", count)
    }

    /// The Mac table’s first column and the audio graph’s category axis.
    static var categoryColumn: String {
        FeatureText.string(
            key: "report.column.category",
            defaultValue: "Category",
            comment: "Spending report: the Mac table’s category column title, and the audio graph’s category axis.",
        )
    }

    /// The Mac table’s count column.
    static var transactionsColumn: String {
        FeatureText.string(
            key: "report.column.transactions",
            defaultValue: "Transactions",
            comment: "Spending report: the Mac table’s column of how many transactions each category has.",
        )
    }

    /// The Mac table’s amount column and the audio graph’s value axis.
    static var amountColumn: String {
        FeatureText.string(
            key: "report.column.amount",
            defaultValue: "Amount",
            comment: "Spending report: the Mac table’s amount column title, and the audio graph’s amount axis.",
        )
    }

    /// The Mac table’s share column.
    static var shareColumn: String {
        FeatureText.string(
            key: "report.column.share",
            defaultValue: "Share",
            comment: "Spending report: the Mac table’s column of each category’s share of spending, such as 16.9%.",
        )
    }
}

import Foundation

/// “Where does my money come from?”: the income report (#184 slice 5, UI Designer's spec). The rest of its
/// wording is the category report's.
extension ReportText {
    static var incomeQuestion: String {
        FeatureText.string(
            "Where does my money come from?",
            comment: "The income-by-category report’s title, a plain question: its row on Reports and its heading.",
        )
    }

    /// The income report's navigation title, Back button and Mac window title.
    static var incomeTitle: String {
        FeatureText.string(
            key: "report.title.income",
            defaultValue: "Income",
            comment: "Navigation title of the income-by-category report, also its Back button and Mac window title.",
        )
    }

    /// An income with no payee or description, in the income drill-down.
    static var income: String {
        FeatureText.string("Income", comment: "Transaction type: money in.")
    }

    static var sourcesOfIncome: String {
        FeatureText.string("Sources of Income", comment: "Income report: the header of the list of category rows.")
    }

    static var incomeFooter: String {
        FeatureText.string(
            "Sorted by amount. Refunds and transfers between your accounts aren’t income.",
            comment: "Income report: the footer under the category rows.",
        )
    }

    /// “Other · 2 sources”: the chart's last bar, combining the smaller sources. Always 2 or more.
    static func otherSources(_ count: Int) -> String {
        FeatureText.plural("Other · %lld sources", one: "Other · %lld source", count)
    }

    /// “Other, 2 sources”: how VoiceOver and the audio graph name the Other bar.
    static func otherSourcesSpoken(_ count: Int) -> String {
        FeatureText.plural("Other, %lld sources", one: "Other, %lld source", count)
    }

    static var noIncomeTitle: String {
        FeatureText.string(
            "No Income",
            comment: "Income report empty state title, above “There’s no income in this period. Try another period.”",
        )
    }

    static var noIncomeMessage: String {
        FeatureText.string(
            "There’s no income in this period. Try another period.",
            comment: "Income report empty state message, under “No Income”.",
        )
    }
}

import Foundation

/// “Where do I spend the most?”: the spending report grouped by payee (#184 slice 4, UI Designer's spec). The
/// rest of its wording is the category report's.
extension ReportText {
    static var payeeQuestion: String {
        FeatureText.string(
            "Where do I spend the most?",
            comment: "The spending-by-payee report’s title, a plain question: its row on Reports and its heading.",
        )
    }

    /// The payee report's navigation title: its Back button, Mac window title and VoiceOver name (UI Designer's
    /// answer on #314). The category report's stays “Spending”.
    static var payeeTitle: String {
        FeatureText.string(
            "Spending by Payee",
            comment: "Navigation title of the spending-by-payee report, also its Back button and Mac window title.",
        )
    }

    static var allPayees: String {
        FeatureText.string("All Payees", comment: "Spending by payee: the header of the list of payee rows.")
    }

    /// The row, and its drill-down's title, for spending with no payee, or whose payee was deleted.
    static var noPayee: String {
        FeatureText.string(
            "No Payee",
            comment: "Spending by payee: the row, and its drill-down’s title, for spending with no payee.",
        )
    }

    static var payeeFooter: String {
        FeatureText.string(
            "Sorted by amount. Refunds reduce spending at their payee. Transfers between your accounts aren’t spending.",
            comment: "Spending by payee: the footer under the payee rows.",
        )
    }

    /// “Other · 2 payees”: the chart's last bar, combining the smaller payees. Always 2 or more.
    static func otherPayees(_ count: Int) -> String {
        FeatureText.plural("Other · %lld payees", one: "Other · %lld payee", count)
    }

    /// “Other, 2 payees”: how VoiceOver and the audio graph name the Other bar.
    static func otherPayeesSpoken(_ count: Int) -> String {
        FeatureText.plural("Other, %lld payees", one: "Other, %lld payee", count)
    }

    /// The Mac table’s first column and the audio graph’s payee axis.
    static var payeeColumn: String {
        FeatureText.string(
            key: "report.column.payee",
            defaultValue: "Payee",
            comment: "Spending by payee: the Mac table’s payee column title, and the audio graph’s payee axis.",
        )
    }
}

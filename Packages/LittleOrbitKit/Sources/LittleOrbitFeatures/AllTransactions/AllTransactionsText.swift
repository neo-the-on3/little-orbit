import Foundation

/// The All Transactions screen's own wording (#243). The empty state is D320.5's, which the search screens use
/// too (D425.1), so both screens share one catalog entry each.
enum AllTransactionsText {
    static var noTransactions: String {
        FeatureText.string(
            "No Transactions",
            comment: "All Transactions and search, when the store has no transactions at all.",
        )
    }

    static var noTransactionsMessage: String {
        FeatureText.string(
            "Transactions you add will appear here.",
            comment: "All Transactions and search, under “No Transactions”, when the store has no transactions at all.",
        )
    }
}

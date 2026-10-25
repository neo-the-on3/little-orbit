import Foundation
import LittleOrbitDomain

/// The wording of search (#28), from the package's String Catalog. Frame copy comes from the #28 Search frames;
/// the rest is standard Apple wording, listed in the pull request to confirm.
enum SearchText {
    static var searchTitle: String {
        FeatureText.string("Search", comment: "iOS search screen title, opened with the magnifying glass on Accounts.")
    }

    static var allTransactionsTitle: String {
        FeatureText.string(
            "All Transactions",
            comment: "macOS sidebar item and its screen title: every transaction, with the toolbar search.",
        )
    }

    static var prompt: String {
        FeatureText.string("Search transactions", comment: "The search field’s placeholder on the search screens.")
    }

    static var searchButton: String {
        FeatureText.string(
            "Search Transactions",
            comment: "Accounts toolbar button that opens search (VoiceOver label).",
        )
    }

    // MARK: Scope bar

    static var all: String {
        FeatureText.string("All", comment: "Search scope bar: every type of transaction.")
    }

    // Search’s own keys, so translators can word each one for where it shows (Tech Architect NB5): the scope bar
    // filters, the summary’s total labels and a row’s fallback title can need different forms in some languages.

    static var expensesScope: String {
        FeatureText.string(
            key: "search.scope.expenses",
            defaultValue: "Expenses",
            comment: "Search scope bar: show only expenses (refunds included).",
        )
    }

    static var incomeScope: String {
        FeatureText.string(
            key: "search.scope.income",
            defaultValue: "Income",
            comment: "Search scope bar: show only income.",
        )
    }

    // MARK: Rows

    /// A result row's title when an expense has no payee or description.
    static var expenseRow: String {
        FeatureText.string(
            key: "search.row.expense",
            defaultValue: "Expense",
            comment: "A search result’s title when the expense has no payee or description.",
        )
    }

    /// A result row's title when income has no payee or description.
    static var incomeRow: String {
        FeatureText.string(
            key: "search.row.income",
            defaultValue: "Income",
            comment: "A search result’s title when the income has no payee or description.",
        )
    }

    static var transfers: String {
        FeatureText.string("Transfers", comment: "Search scope bar: only transfers between your accounts.")
    }

    // MARK: Summary

    /// “14 results”.
    static func results(_ count: Int) -> String {
        FeatureText.plural("%lld results", one: "%lld result", count)
    }

    /// The label under a currency's income total in the summary card.
    static var incomeTotal: String {
        FeatureText.string(
            key: "search.total.income",
            defaultValue: "Income",
            comment: "Search summary card: the label under one currency’s income total.",
        )
    }

    /// The label under a currency's spending total in the summary card: expenses less refunds.
    static var expensesTotal: String {
        FeatureText.string(
            key: "search.total.expenses",
            defaultValue: "Expenses",
            comment: "Search summary card: the label under one currency’s spending total (expenses less refunds).",
        )
    }

    static var net: String {
        FeatureText.string("Net", comment: "Search totals: income minus expenses for one currency.")
    }

    static var moved: String {
        FeatureText.string(
            "Moved between your accounts",
            comment: "Search totals when only transfers match: the amount moved.",
        )
    }

    /// “₹1,000.00 moved” in a day header: a currency with only transfers that day (D56, D111).
    static func movedAmount(_ amount: String) -> String {
        FeatureText.format("%@ moved", amount)
    }

    /// The iOS summary note (D134), hidden when there are none.
    static func upcomingNote(_ count: Int) -> String {
        FeatureText.plural(
            "%lld upcoming matches are listed but not counted.",
            one: "%lld upcoming match is listed but not counted.",
            count,
        )
    }

    /// The macOS footer under the results (S85, S91), with no number.
    static var upcomingFooter: String {
        FeatureText.string(
            "Upcoming matches are listed but not counted.",
            comment: "macOS search footer when any result is dated after today.",
        )
    }

    /// VoiceOver's reading of a muted day header (D120.1): “Upcoming, Sun, 25 Oct, −₹350.00”.
    static func upcomingHeader(day: String, figures: String) -> String {
        FeatureText.format("Upcoming, %1$@, %2$@", day, figures)
    }

    /// VoiceOver's reading of one currency's totals, with the currency's name so it isn't spelled out:
    /// “Indian Rupee: Income ₹0.00, Expenses ₹4,830.00, Net −₹4,830.00”.
    static func spokenTotals(currency: String, income: String, expenses: String, net: String) -> String {
        FeatureText.format("%1$@: Income %2$@, Expenses %3$@, Net %4$@", currency, income, expenses, net)
    }

    /// VoiceOver's reading of one currency's transfers-only total: “Indian Rupee: Moved between your accounts
    /// ₹22,000.00”.
    static func spokenMoved(currency: String, amount: String) -> String {
        FeatureText.format("%1$@: Moved between your accounts %2$@", currency, amount)
    }

    // MARK: Hints

    /// A malformed date was ignored (PM answer 3).
    static var dateHint: String {
        FeatureText.string(
            "Use YYYY-MM-DD",
            comment: "Search hint when an after: or before: date isn’t a real day; that part is ignored.",
        )
    }

    static var yearHint: String {
        FeatureText.string(
            "Use YYYY for year:",
            comment: "Search hint when year: isn’t four digits; that part is ignored.",
        )
    }

    static var typeHint: String {
        FeatureText.string(
            "Use expense, income or transfer for type:",
            comment: "Search hint when type: has another value; that part is ignored.",
        )
    }

    static func hint(for issue: TransactionSearchIssue) -> String {
        switch issue {
        case .invalidDate: dateHint
        case .invalidYear: yearHint
        case .invalidType: typeHint
        }
    }

    // MARK: Empty states

    /// “No Results for “lantern tea house””, a heading in title case (D320.4, D206.1).
    static func noResults(_ query: String) -> String {
        FeatureText.format("No Results for “%@”", query)
    }

    static var noResultsMessage: String {
        FeatureText.string(
            "Check the spelling or try fewer words. Search looks at description, category, payee, tag and notes.",
            comment: "Search empty state under No results for …",
        )
    }

    static var clearSearch: String {
        FeatureText.string(
            "Clear Search",
            comment: "Search empty state button: empties the field and shows every transaction.",
        )
    }

    static var noTransactions: String {
        FeatureText.string("No Transactions", comment: "Search screens when the store has no transactions at all.")
    }

    static var noTransactionsMessage: String {
        FeatureText.string(
            "Transactions you add will appear here.",
            comment: "Search screens when the store has no transactions at all.",
        )
    }

    /// The load failure's title and message (D320.6, as D318.5). A retry button comes with #187.
    static var loadFailedTitle: String {
        FeatureText.string(
            "Couldn’t Load Transactions",
            comment: "Search screens’ title when the store can’t be read.",
        )
    }

    /// The shared “Try again.” entry, whose comment names every place it shows.
    static var loadFailedMessage: String {
        CategoryText.tryAgain
    }

    static var openHint: String {
        FeatureText.string("Opens the transaction to edit", comment: "VoiceOver hint on a search result row.")
    }

    // MARK: Transfer rows

    /// A transfer row's title from the listed account's side (D173.9).
    static func transferTo(_ account: String) -> String {
        FeatureText.format("To %@", account)
    }

    static func transferFrom(_ account: String) -> String {
        FeatureText.format("From %@", account)
    }

    static var anotherAccount: String {
        FeatureText.string(
            "another account",
            comment: "A transfer row’s title when the other account was deleted: To another account.",
        )
    }
}

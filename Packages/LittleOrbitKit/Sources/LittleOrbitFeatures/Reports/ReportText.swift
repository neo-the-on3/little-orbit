import Foundation
import LittleOrbitDomain

/// The wording of Reports and “What do I spend my money on?” (#27 core), from the package's String Catalog.
/// Where no frame gives the wording, it follows Apple's conventions, and the pull request lists it to confirm.
enum ReportText {
    static var reportsTitle: String {
        FeatureText.string(
            "Reports",
            comment:
                "Reports screen title (iOS, pushed from the Accounts home; macOS detail for the sidebar’s Reports item).",
        )
    }

    static var spendingTitle: String {
        FeatureText.string("Spending", comment: "Navigation title of the spending-by-category report.")
    }

    static var spendingQuestion: String {
        FeatureText.string(
            "What do I spend my money on?",
            comment: "The spending-by-category report’s title, a plain question: its row on Reports and its heading.",
        )
    }

    static var period: String {
        FeatureText.string("Period", comment: "Spending report: the period picker’s label.")
    }

    static var currency: String {
        FeatureText.string(
            "Currency",
            comment: "Spending report: the currency picker’s label, shown only with spending in 2 or more currencies.",
        )
    }

    static func periodName(_ period: ReportPeriod) -> String {
        switch period {
        case .thisMonth:
            FeatureText.string("This Month", comment: "Spending report period preset: the current calendar month.")
        case .lastMonth:
            FeatureText.string("Last Month", comment: "Spending report period preset: the previous calendar month.")
        case .thisQuarter:
            FeatureText.string("This Quarter", comment: "Report period preset: the current calendar quarter.")
        case .lastQuarter:
            FeatureText.string("Last Quarter", comment: "Report period preset: the previous calendar quarter.")
        case .thisYear:
            FeatureText.string("This Year", comment: "Spending report period preset: the current calendar year.")
        case .lastYear:
            FeatureText.string("Last Year", comment: "Spending report period preset: the previous calendar year.")
        }
    }

    /// “Q4 2026”: a calendar quarter's title. `year` is already formatted for the locale.
    static func quarterTitle(_ quarter: Int, year: String) -> String {
        FeatureText.format("Q%1$lld %2$@", quarter, year)
    }

    /// “15 Sep 2026 – 14 Oct 2026”: a custom range's title, both end days included.
    static func rangeTitle(from start: String, to end: String) -> String {
        FeatureText.format("%1$@ – %2$@", start, end)
    }

    static var uncategorised: String {
        FeatureText.string(
            "Uncategorised",
            comment:
                "The row for no category: in the transaction form's category picker it saves the transaction without one; in the spending report it's the row, and its drill-down's title, for spending with no category.",
        )
    }

    /// “Food & Dining › Groceries”: a subcategory's row names its parent too (D289.2).
    static func subcategoryName(_ name: String, parent: String) -> String {
        FeatureText.format("%1$@ › %2$@", parent, name)
    }

    static func transactionCount(_ count: Int) -> String {
        FeatureText.plural("%lld transactions", one: "%lld transaction", count)
    }

    /// “Spent in October 2026 · INR · all accounts”, under the total (D318.1; “· all accounts” from #184).
    static func spentCaption(period: String, currencyCode: String, accounts: String) -> String {
        FeatureText.format("Spent in %1$@ · %2$@ · %3$@", period, currencyCode, accounts)
    }

    static var allAccounts: String {
        FeatureText.string(
            "all accounts",
            comment:
                "Spending report caption’s end, “Spent in October 2026 · INR · all accounts”: every account counts.",
        )
    }

    /// “2 accounts”: how many of the shown currency's accounts are ticked, when not all of them are.
    static func accountCount(_ count: Int) -> String {
        FeatureText.plural("%lld accounts", one: "%lld account", count)
    }

    static var accountsTitle: String {
        FeatureText.string(
            "Accounts",
            comment:
                "Spending report: the account filter’s button and sheet title, listing the shown currency’s accounts.",
        )
    }

    static var hiddenAccount: String {
        FeatureText.string(
            "Hidden",
            comment:
                "Spending report account filter: the note on a hidden account’s row. Its spending counts while ticked.",
        )
    }

    static var customRange: String {
        FeatureText.string("Custom Range", comment: "Report period picker: choose your own first and last day.")
    }

    static var customStart: String {
        FeatureText.string("From", comment: "Report custom range: the first day, included.")
    }

    static var customEnd: String {
        FeatureText.string("To", comment: "Report custom range: the last day, included.")
    }

    static var previousPeriod: String {
        FeatureText.string(
            "Previous Period",
            comment: "Report ‹ button (⌘← on macOS): the month, quarter or year before the one shown.",
        )
    }

    static var nextPeriod: String {
        FeatureText.string(
            "Next Period",
            comment: "Report › button (⌘→ on macOS): the month, quarter or year after the one shown.",
        )
    }

    static var tryAgainButton: String {
        FeatureText.string(
            "Try Again",
            comment:
                "Button under “Couldn’t Load Report” that reads the report (and an open drill-down) again (D318.5).",
        )
    }

    /// “16.9% of spending · October 2026 · INR”, under a category's total in its drill-down: the category's share
    /// (D319.7), then the report's period and currency, with no filter wording until #184 adds filters (D319.5).
    /// `share` is the percent formatter's output, sign included; without one the header is the period and currency.
    static func drillDownCaption(share: String?, period: String, currencyCode: String) -> String {
        let periodAndCurrency = FeatureText.format("%1$@ · %2$@", period, currencyCode)
        guard let share else {
            return periodAndCurrency
        }
        return FeatureText.format("%1$@ · %2$@", FeatureText.format("%1$@ of spending", share), periodAndCurrency)
    }

    static var allCategories: String {
        FeatureText.string("All Categories", comment: "Spending report: the header of the list of category rows.")
    }

    static var footer: String {
        FeatureText.string(
            "Sorted by amount. Refunds reduce spending in their category. Transfers between your accounts aren’t spending.",
            comment: "Spending report footer under the category rows.",
        )
    }

    static var emptyTitle: String {
        FeatureText.string(
            "No Expenses",
            comment:
                "Spending report empty state title, above “There are no expenses in this period. Try another period.” (D318.4).",
        )
    }

    static var emptyMessage: String {
        FeatureText.string(
            "There are no expenses in this period. Try another period.",
            comment: "Spending report empty state message, under “No Expenses” (D318.4).",
        )
    }

    static var loadFailedTitle: String {
        FeatureText.string(
            "Couldn’t Load Report",
            comment: "Spending report: the title shown when its data can’t be read.",
        )
    }

    static var tryAgain: String {
        FeatureText.string(
            "Try again.",
            comment:
                "Message under “Couldn’t Load Payees” or “Couldn’t Load Categories” (alerts), and under “Couldn’t Load Report” (the spending report and its drill-down).",
        )
    }

    static var expense: String {
        FeatureText.string(
            "Expense",
            comment:
                "A category's kind, the Categories screen's Expense tab, and the spending drill-down's title for an expense with no payee or description.",
        )
    }
}

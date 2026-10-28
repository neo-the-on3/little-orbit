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
        case .lastSixMonths:
            FeatureText.string(
                "Last 6 Months",
                comment: "Over-time report period preset: this calendar month and the five before it.",
            )
        }
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

    /// “Spent in October 2026 · all accounts · INR”, under the total (D318.1; the account part from #184's
    /// slice 1 spec, D420).
    static func spentCaption(period: String, accounts: String, currencyCode: String) -> String {
        FeatureText.format("Spent in %1$@ · %2$@ · %3$@", period, accounts, currencyCode)
    }

    static var allAccounts: String {
        FeatureText.string(
            "all accounts",
            comment:
                "Report captions’ account part, “Spent in October 2026 · all accounts · INR”: every listed account counts.",
        )
    }

    /// “2 of 3 accounts”: the caption's account part when some of the shown currency's accounts are unticked.
    static func accountsOf(_ included: Int, total: Int) -> String {
        FeatureText.pluralFormat(
            "%1$lld of %2$lld accounts",
            one: "%1$lld of %2$lld account",
            count: total,
            included,
            total,
        )
    }

    /// The Accounts row's value: “All”, or “2 of 3”.
    static func accountsValue(_ included: Int, total: Int) -> String {
        guard included < total else {
            return FeatureText.string(
                key: "report.accounts.all",
                defaultValue: "All",
                comment: "Report Accounts row value when every listed account is ticked: “Accounts  All”.",
            )
        }
        return FeatureText.format("%1$lld of %2$lld", included, total)
    }

    /// “Only INR accounts are listed because the report shows INR.”: the account list's footer.
    static func accountsFooter(currencyCode: String) -> String {
        FeatureText.format("Only %1$@ accounts are listed because the report shows %1$@.", currencyCode)
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
        FeatureText.string("Custom…", comment: "Report period picker: choose your own first and last day.")
    }

    static var bothDatesIncluded: String {
        FeatureText.string(
            "Both dates are included.",
            comment: "Report custom range: the note under the From and To day pickers.",
        )
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

    /// “16.9% of spending · October 2026 · all accounts · INR”, under a category's total in its drill-down: the
    /// category's share (D319.7), then the report's period, account part and currency, as the report's caption
    /// names them (D319.5: the account wording returns with #184). `share` is the percent formatter's output, sign
    /// included; without one the header starts at the period.
    static func drillDownCaption(share: String?, period: String, accounts: String, currencyCode: String) -> String {
        let scope = FeatureText.format("%1$@ · %2$@ · %3$@", period, accounts, currencyCode)
        guard let share else {
            return scope
        }
        return FeatureText.format("%1$@ · %2$@", FeatureText.format("%1$@ of spending", share), scope)
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

import Foundation

// The wording of the iOS budget detail (#25 part 4): the detail frames, D307.2, D307.3, D307.5, D307.8, D308 and
// D309, and the refund and split rows carried from #34 (D233, D237, S72–S75).
extension BudgetText {
    // MARK: Header

    /// “₹1,500.00 unused”: what was left when a past period ended.
    static func unused(_ amount: String) -> String {
        FeatureText.format("%@ unused", amount)
    }

    /// “of ₹9,500.00 available”, under the amount left.
    static func ofAvailable(_ amount: String) -> String {
        FeatureText.format("of %@ available", amount)
    }

    /// “Overspent · limit ₹5,000.00”, under the amount over.
    static func overspentLimit(_ amount: String) -> String {
        FeatureText.format("Overspent · limit %@", amount)
    }

    /// “Ended 30 Sep · of ₹7,000.00”, under a past period's amount.
    static func ended(_ date: String, available: String) -> String {
        FeatureText.format("Ended %1$@ · of %2$@", date, available)
    }

    /// “Spent ₹3,450.00”.
    static func spentAmount(_ amount: String) -> String {
        FeatureText.format("Spent %@", amount)
    }

    /// “resets 1 Nov”, after the days left.
    static func resets(_ date: String) -> String {
        FeatureText.format("resets %@", date)
    }

    static var previousPeriod: String {
        FeatureText.string("Previous Period", comment: "Budget detail: button that shows the period before this one.")
    }

    static var nextPeriod: String {
        FeatureText.string("Next Period", comment: "Budget detail: button that shows the period after this one.")
    }

    // MARK: Facts

    static var limit: String {
        FeatureText.string("Limit", comment: "Budget detail: the label of the current period’s limit.")
    }

    static var limitInThisPeriod: String {
        FeatureText.string(
            "Limit in this period",
            comment: "Budget detail, on a past period: the label of the limit that applied to that period.",
        )
    }

    /// “Carried over from 1–30 Sep 2026”: what the period before passed to this one.
    static func carriedFrom(_ period: String) -> String {
        FeatureText.format("Carried over from %@", period)
    }

    /// “Carried over to 1–31 Oct 2026”: what a past period passed to the next one.
    static func carriedTo(_ period: String) -> String {
        FeatureText.format("Carried over to %@", period)
    }

    static var carryOverOverspendingFact: String {
        FeatureText.string(
            "Carry over overspending",
            comment: "Budget detail, when overspent: the label of whether overspending is taken from the next period.",
        )
    }

    static var onValue: String {
        FeatureText.string("On", comment: "Budget detail: a carry-over switch is on.")
    }

    static var offValue: String {
        FeatureText.string("Off", comment: "Budget detail: a carry-over switch is off.")
    }

    // MARK: Hints

    /// D311.1: “1 expense from USD Wallet (USD) isn’t included.”, the period's other-currency expenses in the
    /// budget's categories, all from one account.
    static func otherCurrencyExpenses(_ count: Int, account: String, currency: String) -> String {
        FeatureText.pluralFormat(
            "%1$lld expenses from %2$@ (%3$@) aren’t included.",
            one: "%1$lld expense from %2$@ (%3$@) isn’t included.",
            count: count,
            count,
            account,
            currency,
        )
    }

    /// D311.1: “3 expenses from 2 accounts in other currencies aren’t included.”, from two or more accounts.
    static func otherCurrencyExpenses(_ count: Int, accounts: Int) -> String {
        FeatureText.format(
            "%1$lld expenses from %2$lld accounts in other currencies aren’t included.",
            count,
            accounts,
        )
    }

    /// D311.1: “This budget counts INR accounts only.”, after the other-currency hint.
    static func countsOnly(_ code: String) -> String {
        FeatureText.format("This budget counts %@ accounts only.", code)
    }

    /// D307.3, S7: no account in the budget's currency, so nothing can count.
    static func noAccountInCurrency(_ code: String) -> String {
        FeatureText.format(
            "You have no %1$@ account, so nothing counts yet. This budget counts %1$@ accounts only.",
            code,
        )
    }

    /// A past period whose limit was changed later (#25 AC 4).
    static func pastLimit(_ old: String, new: String, from date: String) -> String {
        FeatureText.format(
            "The limit was %1$@ in this period. The change to %2$@ applies from %3$@ onwards.",
            old,
            new,
            date,
        )
    }

    // MARK: Sections

    static var categoriesSection: String {
        FeatureText.string("Categories", comment: "Budget detail: header over the budget’s categories.")
    }

    /// “Transactions · 4”.
    static func transactionsSection(_ count: Int) -> String {
        FeatureText.format("Transactions · %lld", count)
    }

    /// “Shopping (incl. Clothes, Electronics)”: a picked parent and the subcategories it covers.
    static func including(_ name: String, _ subcategories: String) -> String {
        FeatureText.format("%1$@ (incl. %2$@)", name, subcategories)
    }

    /// “Food › Coffee”: a picked subcategory under its parent.
    static func path(_ parent: String, _ name: String) -> String {
        FeatureText.format("%1$@ › %2$@", parent, name)
    }

    /// D311.6: the detail's footnote sentence, with the budget's categories joined by `alternatives(_:)`.
    static func detailFootnote(_ categories: String) -> String {
        FeatureText.format(
            "Adding an expense in %@ updates this budget straight away. Transfers never count.",
            categories,
        )
    }

    /// “Restaurants or Coffee”, in the user's language where the platform can (D311.6).
    static func alternatives(_ names: [String]) -> String {
        #if canImport(Darwin)
            names.formatted(.list(type: .or))
        #else
            switch names.count {
            case 0: ""
            case 1: names[0]
            default: names.dropLast().joined(separator: ", ") + " or " + (names.last ?? "")
            }
        #endif
    }

    /// “₹1,000.00 − ₹300.00 + ₹240.00 = ₹940.00” (S72).
    static func total(_ terms: String, _ total: String) -> String {
        FeatureText.format("%1$@ = %2$@", terms, total)
    }

    // MARK: Deleted elsewhere (D309, D311.7)

    /// Its own entry, though #176's “Couldn’t Save Changes” message has the same English, so translators can
    /// word it as a screen title.
    static var deletedTitle: String {
        FeatureText.string(
            key: "budget.detail.deleted.title",
            defaultValue: "This budget no longer exists.",
            comment:
                "Budget detail: the screen’s title when the budget on show was deleted elsewhere. No message or button; Back returns to the Budgets list.",
        )
    }

    // MARK: Transaction rows

    static var refund: String {
        FeatureText.string("Refund", comment: "Budget detail: title of a refund with no payee or description (D233).")
    }

    static var refundOriginalDeleted: String {
        FeatureText.string(
            "Refund (original deleted)",
            comment: "Budget detail: title of a refund whose expense was deleted, with no payee or description (D233).",
        )
    }

    static var split: String {
        FeatureText.string("Split", comment: "Budget detail: marks a row that shows one line of a split expense.")
    }

    static var expense: String {
        FeatureText.string("Expense", comment: "Budget detail: title of an expense with no payee or description.")
    }

    // MARK: No categories (D307.5)

    static var noCategoriesTitle: String {
        FeatureText.string(
            "No Categories",
            comment: "Budget detail empty state title: every category the budget picked was deleted.",
        )
    }

    static var noCategoriesMessage: String {
        FeatureText.string(
            "Pick at least one category to track spending.",
            comment: "Budget detail empty state message, under “No Categories”. Its button is “Edit Budget”.",
        )
    }

    // MARK: Actions

    static var budgetActions: String {
        FeatureText.string("Budget Actions", comment: "Budget detail: VoiceOver name of the toolbar’s ⋯ menu.")
    }

    static var changeBudgetLimit: String {
        FeatureText.string(
            "Change Budget Limit",
            comment: "Budget detail: menu item and sheet title for changing the limit from this period on.",
        )
    }

    static var deleteBudget: String {
        FeatureText.string("Delete Budget", comment: "Budget detail: the destructive action that deletes the budget.")
    }

    /// “Delete the “Shopping” budget?” with curly quotes (D307 amendment, D199.3).
    static func deleteTitle(_ name: String) -> String {
        FeatureText.format("Delete the “%@” budget?", name)
    }

    static var deleteMessage: String {
        FeatureText.string(
            "The budget and its history are removed. Your transactions aren’t changed and still count in Reports.",
            comment: "Delete budget confirmation message, under “Delete the “%@” budget?”.",
        )
    }

    /// “Was ₹7,000.00.”, under the new limit.
    static func was(_ amount: String) -> String {
        FeatureText.format("Was %@.", amount)
    }

    /// “Change limit to ₹8,000.00?”.
    static func changeLimitTitle(_ amount: String) -> String {
        FeatureText.format("Change limit to %@?", amount)
    }

    /// “Applies from this period (1–31 Oct 2026) onwards. Earlier periods keep their limit of ₹7,000.00.”
    static func changeLimitMessage(_ period: String, old: String) -> String {
        FeatureText.format(
            "Applies from this period (%1$@) onwards. Earlier periods keep their limit of %2$@.",
            period,
            old,
        )
    }

    static var applyFromThisPeriod: String {
        FeatureText.string(
            "Apply from This Period",
            comment: "Change limit action sheet: the button that saves the new limit from the current period on.",
        )
    }

    static var save: String {
        FeatureText.string("Save", comment: "Change Budget Limit sheet: the button that saves the new limit.")
    }
}

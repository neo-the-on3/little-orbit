import Foundation

// The Mac Budgets screen's own text (#25 part 5): its Budget menu, right-click menu and Today, the list's count
// line, and the name of a Duplicate's copy (D307.6). Menu items that open a sheet or an alert end in “…”.
extension BudgetText {
    static var budgetMenu: String {
        FeatureText.string("Budget", comment: "Mac menu bar: the Budget menu, with the commands for budgets.")
    }

    static var newBudgetEllipsis: String {
        FeatureText.string(
            "New Budget…",
            comment: "Mac Budget menu, right-click menu and the empty list’s button: opens New Budget.",
        )
    }

    static var openBudget: String {
        FeatureText.string("Open Budget", comment: "Mac budget list right-click menu: shows the budget’s detail.")
    }

    static var editBudgetEllipsis: String {
        FeatureText.string("Edit Budget…", comment: "Mac Budget menu and right-click menu: opens Edit Budget.")
    }

    static var changeBudgetLimitEllipsis: String {
        FeatureText.string(
            "Change Budget Limit…",
            comment: "Mac Budget menu and budget detail: opens Change Budget Limit for this period onwards.",
        )
    }

    static var duplicate: String {
        FeatureText.string(
            "Duplicate",
            comment: "Mac Budget menu and right-click menu: saves a copy of the budget straight away (D307.6).",
        )
    }

    static var showPreviousPeriod: String {
        FeatureText.string(
            "Show Previous Period",
            comment: "Mac Budget menu and right-click menu: shows the budget’s period before the one on show.",
        )
    }

    static var showNextPeriod: String {
        FeatureText.string(
            "Show Next Period",
            comment: "Mac Budget menu and right-click menu: shows the budget’s period after the one on show.",
        )
    }

    static var showCurrentPeriod: String {
        FeatureText.string(
            "Show Current Period",
            comment: "Mac Budget menu: goes back to the budget’s current period from a past one.",
        )
    }

    static var today: String {
        FeatureText.string(
            "Today",
            comment: "Mac budget detail: button next to the period arrows that goes back to the current period.",
        )
    }

    static var deleteBudgetEllipsis: String {
        FeatureText.string(
            "Delete Budget…",
            comment: "Mac Budget menu, right-click menu and Edit Budget: asks before deleting the budget.",
        )
    }

    // MARK: Table columns

    static var budgetColumn: String {
        FeatureText.string("Budget", comment: "Mac menu bar: the Budget menu, with the commands for budgets.")
    }

    static var progressColumn: String {
        FeatureText.string("Progress", comment: "Mac budget list: the column with each budget’s bar.")
    }

    static var spentColumn: String {
        FeatureText.string("Spent", comment: "Mac budget list: the column with spent of what’s available.")
    }

    static var leftColumn: String {
        FeatureText.string("Left", comment: "Mac budget list: the column with what’s left, unused or over.")
    }

    static var periodColumn: String {
        FeatureText.string("Period", comment: "Budget form: the section with the start date and repeat.")
    }

    static var dateColumn: String {
        FeatureText.string("Date", comment: "Mac budget detail: the transactions table’s date column.")
    }

    static var payeeColumn: String {
        FeatureText.string("Payee", comment: "Mac budget detail: the transactions table’s payee column.")
    }

    static var categoryColumn: String {
        FeatureText.string("Category", comment: "Transaction form: the category picker’s title.")
    }

    static var accountColumn: String {
        FeatureText.string("Account", comment: "Mac budget detail: the transactions table’s account column.")
    }

    static var amountColumn: String {
        FeatureText.string("Amount", comment: "Mac budget detail: the transactions table’s amount column.")
    }

    /// “Categories: Shopping trips (incl. Clothes, Electronics)”, under the Mac budget detail's figures: the iOS
    /// detail's categories text, in the categories' sort order (D312.2, D313.7).
    static func categoriesLine(_ categories: String) -> String {
        FeatureText.format("Categories: %@", categories)
    }

    /// “1 budget” or “5 budgets”, with the catalog's plural variants (D313.4).
    static func budgetCount(_ count: Int) -> String {
        FeatureText.plural("%lld budgets", one: "%lld budget", count)
    }

    /// “1 overspent”, after the count, with the catalog's plural variants (D313.4).
    static func overspentCount(_ count: Int) -> String {
        FeatureText.plural("%lld overspent", one: "%lld overspent", count)
    }

    /// “Eating out copy”, then “Eating out copy 2”, like the Finder (D307.6). Two entries, not a plural. `name`
    /// is the original's, shortened by the caller when the copy's name wouldn't fit (D313.2).
    static func copyName(_ name: String, number: Int) -> String {
        number == 1 ? FeatureText.format("%@ copy", name) : FeatureText.format("%@ copy %lld", name, number)
    }
}

import Foundation
import LittleOrbitDomain

/// The wording of the New Budget and Edit Budget form (#25 design: New budget – form, Repeat – custom,
/// Categories – multi-select, validation errors and Recalculate past periods frames; D307.6, D307.7).
extension BudgetText {
    // MARK: Sheet

    static var newBudget: String {
        FeatureText.string(
            "New Budget",
            comment: "Budget form sheet title for a new budget, and the Budgets screen’s + button’s VoiceOver name.",
        )
    }

    static var editBudget: String {
        FeatureText.string("Edit Budget", comment: "Budget form sheet title when editing a budget.")
    }

    static var createBudget: String {
        FeatureText.string(
            "Create Budget",
            comment: "Budgets screen empty state: the button that opens the New Budget form.",
        )
    }

    // MARK: Sections and rows

    static var nameHeader: String { CategoryText.name }

    /// “Name”, the name field's placeholder, as the validation frame draws it (D309.4).
    static var namePrompt: String { CategoryText.name }

    static var limitHeader: String {
        FeatureText.string("Limit", comment: "Budget form: the limit section header and the limit field’s label.")
    }

    static var currency: String {
        FeatureText.string("Currency", comment: "Budget form: the currency row’s label.")
    }

    static var currencyFootnote: String {
        FeatureText.string(
            "Defaults to your default currency. Expenses in other currencies aren’t counted.",
            comment: "Budget form: the footnote under the limit and currency.",
        )
    }

    /// “INR — Indian Rupee”, a currency picker choice.
    static func currencyTitle(_ code: String, name: String) -> String {
        FeatureText.format("%1$@ — %2$@", code, name)
    }

    static var categoriesHeader: String {
        FeatureText.string("Categories", comment: "Settings row and screen title: the category manager.")
    }

    static var expenseCategories: String {
        FeatureText.string(
            "Expense categories",
            comment: "Budget form: the row that opens the Categories screen. Its value lists the picked categories.",
        )
    }

    static var categoriesFootnote: String {
        FeatureText.string(
            "A parent category includes its subcategories.",
            comment: "Budget form: the footnote under the categories row.",
        )
    }

    static var none: String {
        FeatureText.string("None", comment: "Budget form: the categories row’s value when none are picked.")
    }

    /// “Restaurants, Coffee”: the picked categories, in the user's language where the platform can.
    static func shortList(_ names: [String]) -> String {
        #if canImport(Darwin)
            names.formatted(.list(type: .and, width: .narrow))
        #else
            names.joined(separator: ", ")
        #endif
    }

    static var periodHeader: String {
        FeatureText.string("Period", comment: "Budget form: the section with the start date and repeat.")
    }

    static var starts: String {
        FeatureText.string("Starts", comment: "Budget form: the start date row’s label.")
    }

    static var repeatTitle: String {
        FeatureText.string("Repeat", comment: "Budget form: the repeat row’s label, and the Repeat screen’s title.")
    }

    static var periodFootnote: String {
        FeatureText.string(
            "Each period starts on the start day and ends the day before the next one.",
            comment: "Budget form: the footnote under the start date and repeat.",
        )
    }

    static var monthEndFootnote: String {
        FeatureText.string(
            "Months without that day start on their last day, e.g. from 31 Jan 2027: 31 Jan–27 Feb, 28 Feb–30 Mar, 31 Mar–29 Apr.",
            comment:
                "Budget form: added to the period footnote when periods are months or years. The example is monthly periods from 31 January 2027. The dates are only an example: write them in your language’s usual date style.",
        )
    }

    static var carryOverHeader: String {
        FeatureText.string("Carry-over", comment: "Budget form: the section with the two carry-over switches.")
    }

    static var carryOverUnspent: String {
        FeatureText.string(
            "Carry over unspent",
            comment: "Budget form: switch. On, money left in a period is added to the next one (D307.1).",
        )
    }

    static var carryOverOverspending: String {
        FeatureText.string(
            "Carry over overspending",
            comment: "Budget form: switch. On, going over in a period is taken from the next one (D307.1).",
        )
    }

    static var carryOverFootnote: String {
        FeatureText.string(
            "Unspent money is added to the next period. With overspending on, going over is taken from the next period.",
            comment: "Budget form: the footnote under the carry-over switches.",
        )
    }

    // MARK: Categories screen

    /// “Expense categories · 2 selected”.
    static func categoriesHeader(_ count: Int) -> String {
        FeatureText.plural(
            "Expense categories · %lld selected",
            one: "Expense categories · %lld selected",
            count,
        )
    }

    /// “3 subcategories” under a parent on the Categories screen.
    static func subcategoryCount(_ count: Int) -> String {
        FeatureText.plural("%lld subcategories", one: "%lld subcategory", count)
    }

    static var categoriesScreenFootnote: String {
        FeatureText.string(
            "Selecting a parent includes all its subcategories, also ones added later. Only expense categories are listed; income and transfers never count towards a budget.",
            comment: "Budget form, Categories screen: the footnote under the list.",
        )
    }

    // MARK: Repeat screen

    static var custom: String {
        FeatureText.string(
            "Custom",
            comment: "Budget form, Repeat screen: the custom repeat choice and its section header.",
        )
    }

    /// “Every 3”, the custom repeat's stepper.
    static func every(_ count: Int) -> String {
        FeatureText.format("Every %lld", count)
    }

    static var unitLabel: String {
        FeatureText.string("Unit", comment: "Budget form, Repeat screen: the custom repeat’s unit picker label.")
    }

    /// “Week” after “Every 1”, “Weeks” after “Every 3”: the custom repeat's unit, singular or plural by the count
    /// (D309.5). The count isn't in the text, so the singular and the plural are separate catalog entries picked
    /// here: a plural variation has to show its number.
    static func unit(_ unit: BudgetRecurrenceUnit, count: Int) -> String {
        let words: (one: FeatureText.Value, other: FeatureText.Value) =
            switch unit {
            case .day: ("Day", "Days")
            case .week: ("Week", "Weeks")
            case .month: ("Month", "Months")
            case .year: ("Year", "Years")
            }
        return count == 1
            ? FeatureText.string(
                words.one,
                comment: "Budget form, Repeat screen: the custom repeat’s unit after “Every 1”, singular (D309.5).",
            )
            : FeatureText.string(
                words.other,
                comment:
                    "Budget form, Repeat screen: the custom repeat’s unit after “Every N” above 1, plural (D309.5).",
            )
    }

    static var customFootnote: String {
        FeatureText.string(
            "Every 1 to 99 days, weeks, months or years.",
            comment: "Budget form, Repeat screen: the footnote under the custom repeat.",
        )
    }

    static var nextPeriods: String {
        FeatureText.string(
            "Next periods",
            comment: "Budget form, Repeat screen: the header over the current period and the two after it.",
        )
    }

    static var thisPeriod: String {
        FeatureText.string("This period", comment: "Budget form, Repeat screen: marks the period containing today.")
    }

    // MARK: Errors

    /// “There’s already a budget named “Eating out”.” (D307.6).
    static func duplicateName(_ name: String) -> String {
        FeatureText.format("There’s already a budget named “%@”.", name)
    }

    /// “Enter a limit above ₹0.”
    static func limitAbove(_ zero: String) -> String {
        FeatureText.format("Enter a limit above %@.", zero)
    }

    /// “Enter a limit like 1,25,000.00.”
    static func limitLike(_ example: String) -> String {
        FeatureText.format("Enter a limit like %@.", example)
    }

    /// “JPY amounts have no decimal places.”, “INR amounts can have up to 2 decimal places.”
    static func decimals(_ code: String, allowed: Int) -> String {
        guard allowed > 0 else {
            return FeatureText.format("%@ amounts have no decimal places.", code)
        }
        return FeatureText.pluralFormat(
            "%1$@ amounts can have up to %2$lld decimal places.",
            one: "%1$@ amounts can have up to %2$lld decimal place.",
            count: allowed,
            code,
            allowed,
        )
    }

    static var chooseCategory: String {
        FeatureText.string(
            "Choose at least one expense category.",
            comment: "Budget form: error under the categories row when none are picked.",
        )
    }

    /// Under “Couldn’t Save Changes” when the budget was deleted while its sheet was open (D309.3).
    static var budgetNoLongerExists: String {
        FeatureText.string(
            "This budget no longer exists.",
            comment:
                "Alert message under “Couldn’t Save Changes”: the budget being edited was deleted before Save, so nothing was saved.",
        )
    }

    static var categoriesChanged: String {
        FeatureText.string(
            "A category was deleted or changed. Check the categories and try again.",
            comment:
                "Alert message under “Couldn’t Save Changes”: a picked category was deleted or became an income category in another window.",
        )
    }

    // MARK: Recalculate past periods (D307.7)

    static var recalculateTitle: String {
        FeatureText.string(
            "Recalculate Past Periods?",
            comment:
                "Action sheet title when saving a new start date or repeat for a budget with past periods (D307.7).",
        )
    }

    /// “Past periods of “Eating out” are recalculated, …”
    static func recalculateMessage(_ name: String) -> String {
        FeatureText.format(
            "Past periods of “%@” are recalculated, so their spent and carry-over can change. Each limit keeps the date it applies from.",
            name,
        )
    }
}

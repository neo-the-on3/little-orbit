import Foundation
import LittleOrbitDomain

/// The wording of the iOS Budgets list (#25), from the package's String Catalog. The empty state follows the
/// Budgets frames; the rest follows D308 and its amendments, and the D307 amendment for below 0 available.
enum BudgetText {
    // MARK: Screen

    static var title: String {
        FeatureText.string("Budgets", comment: "Budgets screen title, pushed from the home screen’s Budgets row.")
    }

    static var emptyTitle: String {
        FeatureText.string("No budgets yet", comment: "Budgets screen empty state: the title, read as a heading.")
    }

    static var emptyMessage: String {
        FeatureText.string(
            "Set a spending limit for a group of expense categories, like Eating out or Groceries. It resets every week, fortnight, month or year.",
            comment: "Budgets screen empty state: the message under “No budgets yet”.",
        )
    }

    static var footnote: String {
        FeatureText.string(
            "Spent = expenses in the budget’s categories and subcategories, minus refunds. Transfers never count. Near limit is 90% or more.",
            comment: "Budgets screen: the footnote under the list.",
        )
    }

    static var couldntLoadTitle: String {
        FeatureText.string(
            "Couldn’t Load Budgets",
            comment:
                "Alert title: the budget list couldn’t be read. Its message is “Try again.” and its only button is OK.",
        )
    }

    static var loadFailed: CategoryAlert {
        CategoryAlert(title: couldntLoadTitle, message: CategoryText.tryAgain)
    }

    // MARK: Row status

    /// The day before a budget's start date (D308 amendment).
    static var startsTomorrow: String {
        FeatureText.string(
            "Starts tomorrow",
            comment: "Budget row status: the budget starts tomorrow. Shown instead of the figures before it starts.",
        )
    }

    /// "Starts 1 Nov", or "Starts 3 Jan 2027" in another year (D308 amendment).
    static func starts(_ date: String) -> String {
        FeatureText.format("Starts %@", date)
    }

    /// A budget whose categories were all deleted (D307.5, D308 amendment 2).
    static var noCategories: String {
        FeatureText.string(
            "No categories",
            comment: "Budget row status: every category the budget picked was deleted, so it can’t count anything.",
        )
    }

    static var nothingSpent: String {
        FeatureText.string(
            "Nothing spent yet",
            comment: "Budget row status: nothing is spent in the current period.",
        )
    }

    /// "₹6,050.00 left".
    static func left(_ amount: String) -> String {
        FeatureText.format("%@ left", amount)
    }

    /// "₹1,200.00 over".
    static func over(_ amount: String) -> String {
        FeatureText.format("%@ over", amount)
    }

    /// Read before the amount left by VoiceOver, as the warning symbol's words.
    static var nearLimit: String {
        FeatureText.string(
            "Near limit",
            comment: "VoiceOver, on a budget row: the budget has spent 90% or more of what’s available.",
        )
    }

    /// Read before the amount over by VoiceOver, as the warning symbol's words.
    static var overspent: String {
        FeatureText.string(
            "Overspent",
            comment: "VoiceOver, on a budget row: the budget has spent more than what’s available.",
        )
    }

    // MARK: Row details

    /// "₹3,450.00 of ₹9,500.00": spent of what's available.
    static func spentOf(_ spent: String, _ available: String) -> String {
        FeatureText.format("%1$@ of %2$@", spent, available)
    }

    /// "₹11,250.00 of ₹12,000.00 · 94%": near the limit, with the share spent.
    static func spentOf(_ spent: String, _ available: String, percent: Int) -> String {
        FeatureText.format("%1$@ of %2$@ · %3$lld%%", spent, available, percent)
    }

    /// "₹0.00 spent", below 0 available (D307 amendment).
    static func spent(_ amount: String) -> String {
        FeatureText.format("%@ spent", amount)
    }

    /// "−₹500.00 available", below 0 available (D307 amendment).
    static func available(_ amount: String) -> String {
        FeatureText.format("%@ available", amount)
    }

    /// "94%", read by VoiceOver after the amounts (D308.6).
    static func percent(_ value: Int) -> String {
        FeatureText.format("%lld%%", value)
    }

    /// "Monthly · 12 days left", or "₹0.00 spent · −₹500.00 available".
    static func pair(_ first: String, _ second: String) -> String {
        FeatureText.format("%1$@ · %2$@", first, second)
    }

    /// "12 days left", or "Last day" on a period's last day (D308.3).
    static func daysLeft(_ count: Int) -> String {
        guard count != 1 else {
            return FeatureText.string("Last day", comment: "Budget row: today is the current period’s last day.")
        }
        return FeatureText.plural("%lld days left", one: "%lld day left", count)
    }

    static func recurrence(_ recurrence: BudgetRecurrence) -> String {
        switch recurrence {
        case .weekly:
            FeatureText.string("Weekly", comment: "A budget that repeats every week.")
        case .fortnightly:
            FeatureText.string("Fortnightly", comment: "A budget that repeats every two weeks.")
        case .monthly:
            FeatureText.string("Monthly", comment: "A budget that repeats every month.")
        case .yearly:
            FeatureText.string("Yearly", comment: "A budget that repeats every year.")
        case .custom(let every, let unit):
            custom(every, unit)
        }
    }

    private static func custom(_ count: Int, _ unit: BudgetRecurrenceUnit) -> String {
        switch unit {
        case .day: FeatureText.plural("Every %lld days", one: "Every day", count)
        case .week: FeatureText.plural("Every %lld weeks", one: "Every week", count)
        case .month: FeatureText.plural("Every %lld months", one: "Every month", count)
        case .year: FeatureText.plural("Every %lld years", one: "Every year", count)
        }
    }
}

import Foundation

// The budget sentences in the category delete alert and the Merge and Move To footnotes (#25 part 6, D295.1,
// D307.5 with its amendments). Each is a whole catalog phrase; the budgets' names and counts come from the
// category use cases.
extension CategoryText {
    /// What leads the delete alert's budget sentence (D307 amendment 2).
    enum BudgetRemovalLead: Equatable {
        /// Nothing uses the category, so the delete goes ahead straight away: “This also removes …”.
        case unused
        /// Exactly 1 transaction or split line uses it: “Leaving it uncategorised also removes …”.
        case one
        /// 2 or more use it: “Leaving them uncategorised also removes …”.
        case several

        init(usedCount: Int) {
            switch usedCount {
            case 0: self = .unused
            case 1: self = .one
            default: self = .several
            }
        }
    }

    /// "This also removes “Groceries” from the budget “Monthly food”, leaving it with no categories." It goes
    /// right before “Deleting can’t be undone.” (D307 amendment 2). `nil` when no budget picks the category or
    /// a subcategory deleted with it.
    static func budgetRemoval(
        category: String,
        budgetNames: [String],
        leftWithoutCategories: Int,
        lead: BudgetRemovalLead,
    ) -> String? {
        guard let only = budgetNames.first else {
            return nil
        }
        if budgetNames.count == 1 {
            return leftWithoutCategories > 0
                ? removalFromBudgetLeavingIt(category, only, lead: lead)
                : removalFromBudget(category, only, lead: lead)
        }
        return removalFromBudgets(category, budgetNames.count, leftWithoutCategories, lead: lead)
    }

    private static func removalFromBudget(_ category: String, _ budget: String, lead: BudgetRemovalLead) -> String {
        switch lead {
        case .unused:
            FeatureText.format("This also removes “%1$@” from the budget “%2$@”.", category, budget)
        case .one:
            FeatureText.format(
                "Leaving it uncategorised also removes “%1$@” from the budget “%2$@”.",
                category,
                budget,
            )
        case .several:
            FeatureText.format(
                "Leaving them uncategorised also removes “%1$@” from the budget “%2$@”.",
                category,
                budget,
            )
        }
    }

    private static func removalFromBudgetLeavingIt(
        _ category: String,
        _ budget: String,
        lead: BudgetRemovalLead,
    ) -> String {
        switch lead {
        case .unused:
            FeatureText.format(
                "This also removes “%1$@” from the budget “%2$@”, leaving it with no categories.",
                category,
                budget,
            )
        case .one:
            FeatureText.format(
                "Leaving it uncategorised also removes “%1$@” from the budget “%2$@”, leaving it with no categories.",
                category,
                budget,
            )
        case .several:
            FeatureText.format(
                "Leaving them uncategorised also removes “%1$@” from the budget “%2$@”, leaving it with no categories.",
                category,
                budget,
            )
        }
    }

    /// 2 or more budgets; `left` of them end up with no categories.
    private static func removalFromBudgets(
        _ category: String,
        _ count: Int,
        _ left: Int,
        lead: BudgetRemovalLead,
    ) -> String {
        switch (lead, left) {
        case (.unused, 0):
            FeatureText.format("This also removes “%1$@” from %2$lld budgets.", category, count)
        case (.unused, 1):
            FeatureText.format(
                "This also removes “%1$@” from %2$lld budgets, leaving 1 with no categories.",
                category,
                count,
            )
        case (.unused, _):
            FeatureText.format(
                "This also removes “%1$@” from %2$lld budgets, leaving %3$lld with no categories.",
                category,
                count,
                left,
            )
        case (.one, 0):
            FeatureText.format("Leaving it uncategorised also removes “%1$@” from %2$lld budgets.", category, count)
        case (.one, 1):
            FeatureText.format(
                "Leaving it uncategorised also removes “%1$@” from %2$lld budgets, leaving 1 with no categories.",
                category,
                count,
            )
        case (.one, _):
            FeatureText.format(
                "Leaving it uncategorised also removes “%1$@” from %2$lld budgets, leaving %3$lld with no categories.",
                category,
                count,
                left,
            )
        case (.several, 0):
            FeatureText.format(
                "Leaving them uncategorised also removes “%1$@” from %2$lld budgets.",
                category,
                count,
            )
        case (.several, 1):
            FeatureText.format(
                "Leaving them uncategorised also removes “%1$@” from %2$lld budgets, leaving 1 with no categories.",
                category,
                count,
            )
        case (.several, _):
            FeatureText.format(
                "Leaving them uncategorised also removes “%1$@” from %2$lld budgets, leaving %3$lld with no categories.",
                category,
                count,
                left,
            )
        }
    }

    // MARK: Merge (D295.1)

    /// "25 transactions and the budget “Monthly food” will use Food & Dining." (other: “… and 2 budgets will
    /// use …”). Without budgets it's `willUse(count:target:)`.
    static func willUse(count: Int, target: String, budgetNames: [String]) -> String {
        guard let only = budgetNames.first else {
            return willUse(count: count, target: target)
        }
        if budgetNames.count == 1 {
            return FeatureText.pluralFormat(
                "%1$lld transactions and the budget “%2$@” will use %3$@.",
                one: "%1$lld transaction and the budget “%2$@” will use %3$@.",
                count: count,
                count,
                only,
                target,
            )
        }
        return FeatureText.pluralFormat(
            "%1$lld transactions and %2$lld budgets will use %3$@.",
            one: "%1$lld transaction and %2$lld budgets will use %3$@.",
            count: count,
            count,
            budgetNames.count,
            target,
        )
    }

    // MARK: Move To (D295.1)

    /// "Food & Dining, Groceries and Restaurants are deleted after the move; budgets that used them now use
    /// Shopping." Without a target or a budget it's `deletedAfterMove(_:)`.
    static func deletedAfterMove(_ names: [String], budgetsMoveTo target: String) -> String {
        if names.count == 1 {
            return FeatureText.format(
                "%1$@ is deleted after the move; budgets that used it now use %2$@.",
                names[0],
                target,
            )
        }
        return FeatureText.format(
            "%1$@ are deleted after the move; budgets that used them now use %2$@.",
            list(names),
            target,
        )
    }
}

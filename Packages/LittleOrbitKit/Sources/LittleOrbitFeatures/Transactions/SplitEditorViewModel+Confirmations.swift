import Foundation
import LittleOrbitDomain

/// A refund of the expense being edited, by the category it counts in. On Schema V1 a refund has no link to a
/// split line, so a line holds the refunds in its own category; #126 links them to the line itself.
public struct SplitRefundShare: Equatable, Sendable {
    public var categoryID: UUID?
    public var amount: Decimal

    public init(categoryID: UUID?, amount: Decimal) {
        self.categoryID = categoryID
        self.amount = amount
    }
}

/// A Remove Split or line delete confirmation: the title, the message, and the line it deletes, if any.
public struct SplitConfirmation: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var message: String
}

/// The Remove Split confirmation (D97, D219.3) and the confirmation for deleting a line that holds refunds
/// (D112, D218.3, D219.1, D219.2, D219.5, D220). A line with no refunds is deleted straight away.
extension SplitEditorViewModel {
    /// "Remove Split?" with "This becomes a ₹1,000.00 Groceries expense, the largest line." and, when there are
    /// refunds, where they go. An income split reads "This becomes ₹1,000.00 of Salary income, the largest
    /// line.", with the largest line's amount and no refund sentence (D245). It always shows, since it names the
    /// kept category: the one the save keeps, by `SplitRemoval.keptCategory`, so an archived category is named
    /// and a deleted one, or one of the other kind, reads Uncategorised (D97).
    public var removeSplitConfirmation: SplitConfirmation {
        let splits = plan.splits(for: UUID())
        let kept = SplitRemoval.keptLine(of: splits)
        let keptCategory =
            if let removalCategories {
                SplitRemoval.keptCategory(of: splits, type: isIncome ? .income : .expense, in: removalCategories)
            } else {
                kept?.categoryID
            }
        let category = name(of: keptCategory)
        let total = money(self.total)
        let count = refundSource().count
        let message =
            if isIncome {
                FeatureText.format(
                    "This becomes %1$@ of %2$@ income, the largest line.",
                    money(kept?.amount ?? 0),
                    category,
                )
            } else {
                expenseRemovalMessage(total, category, count)
            }
        return SplitConfirmation(
            id: kept?.id ?? UUID(),
            title: FeatureText.string("Remove Split?", comment: "Title of the Remove Split confirmation (D219.3)."),
            message: message,
        )
    }

    /// D219.3's expense message, with its refund sentence for one, both or all of them.
    private func expenseRemovalMessage(_ total: String, _ category: String, _ count: Int) -> String {
        switch count {
        case 0:
            FeatureText.format("This becomes a %1$@ %2$@ expense, the largest line.", total, category)
        case 1:
            FeatureText.format(
                "This becomes a %1$@ %2$@ expense, the largest line. Its refund stays linked and moves to %2$@.",
                total,
                category,
            )
        case 2:
            FeatureText.format(
                "This becomes a %1$@ %2$@ expense, the largest line. Both refunds stay linked and move to %2$@.",
                total,
                category,
            )
        default:
            FeatureText.format(
                "This becomes a %1$@ %2$@ expense, the largest line. All %3$lld refunds stay linked and move to %2$@.",
                total,
                category,
                count,
            )
        }
    }

    /// The confirmation for deleting `line`, or `nil` when it holds no refunds, so it's deleted straight away
    /// (D219.4).
    public func deleteConfirmation(for line: UUID) -> SplitConfirmation? {
        guard let deleted = lines.first(where: { $0.id == line }), let categoryID = deleted.categoryID else {
            return nil
        }
        let held = refundSource().filter { $0.categoryID == categoryID }
        guard !held.isEmpty else {
            return nil
        }
        let remaining = lines.filter { $0.id != line }
        let title = FeatureText.format("Delete the %@ Line?", name(of: categoryID))
        let refunded = money(held.reduce(Decimal(0)) { $0 + $1.amount })
        guard remaining.count >= 2 else {
            return SplitConfirmation(id: line, title: title, message: becomesMessage(remaining, held.count, refunded))
        }
        let after = SplitPlan(remaining, total: total, currencyCode: currencyCode)
        // The largest line as it shows after the delete, the first on a tie; never a ₹0.00 line (D219.5).
        var receiving: SplitLine?
        for candidate in after.lines where candidate.amount > 0 {
            if receiving == nil || candidate.amount > receiving?.amount ?? 0 {
                receiving = candidate
            }
        }
        var leftToAssign: String?
        if case .leftToAssign(let amount) = after.totalIssue {
            leftToAssign = money(amount)
        }
        let message =
            if let receiving {
                largestMessage(name(of: receiving.categoryID), held.count, refunded, leftToAssign)
            } else {
                firstMessage(name(of: after.lines.first?.categoryID), held.count, refunded, money(after.remaining))
            }
        return SplitConfirmation(id: line, title: title, message: message)
    }

    /// Deleting a line of a two-line split leaves a normal expense (D219.1, D220.1).
    private func becomesMessage(_ remaining: [SplitLineDraft], _ count: Int, _ refunded: String) -> String {
        let category = name(of: remaining.first?.categoryID)
        let total = money(self.total)
        return count == 1
            ? FeatureText.format(
                "This becomes a %1$@ %2$@ expense. Its %3$@ refund stays linked and moves to %2$@.",
                total,
                category,
                refunded,
            )
            : FeatureText.format(
                "This becomes a %1$@ %2$@ expense. Its %3$lld refunds (%4$@) stay linked and move to %2$@.",
                total,
                category,
                count,
                refunded,
            )
    }

    /// The refunds go to the largest remaining line, with what's then left to assign, if anything (D219.2).
    private func largestMessage(_ category: String, _ count: Int, _ refunded: String, _ left: String?) -> String {
        switch (count == 1, left) {
        case (true, let left?):
            FeatureText.format(
                "Its %1$@ refund moves to %2$@, the largest remaining line. %3$@ is then left to assign.",
                refunded,
                category,
                left,
            )
        case (true, nil):
            FeatureText.format("Its %1$@ refund moves to %2$@, the largest remaining line.", refunded, category)
        case (false, let left?):
            FeatureText.format(
                "Its %1$lld refunds (%2$@) move to %3$@, the largest remaining line. %4$@ is then left to assign.",
                count,
                refunded,
                category,
                left,
            )
        case (false, nil):
            FeatureText.format(
                "Its %1$lld refunds (%2$@) move to %3$@, the largest remaining line.",
                count,
                refunded,
                category,
            )
        }
    }

    /// Every remaining line is at ₹0.00, so the refunds go to the first one and all of the total is left to
    /// assign (D220.2).
    private func firstMessage(_ category: String, _ count: Int, _ refunded: String, _ left: String) -> String {
        count == 1
            ? FeatureText.format(
                "Its %1$@ refund moves to %2$@, the first remaining line. %3$@ is then left to assign.",
                refunded,
                category,
                left,
            )
            : FeatureText.format(
                "Its %1$lld refunds (%2$@) move to %3$@, the first remaining line. %4$@ is then left to assign.",
                count,
                refunded,
                category,
                left,
            )
    }

    /// A picker option's name, or else a stored category's, so an archived line's category is named too.
    private func name(of category: UUID?) -> String {
        categories.first { $0.id == category }?.name
            ?? removalCategories?.first { $0.id == category && $0.deletedAt == nil }?.name
            ?? TransactionText.uncategorised
    }
}

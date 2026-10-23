import Foundation

/// Turning a split back into a single-category transaction (D97.2). Removing a split is always allowed, even
/// when the stored lines break a D64 rule, so a bad split can always be undone by hand.
public enum SplitRemoval {
    /// The line whose category a removed split keeps: the largest line, or the first of the largest on a tie.
    /// `nil` when there are no live lines.
    public static func keptLine(of splits: [TransactionSplit]) -> TransactionSplit? {
        let ordered = splits.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
        guard var kept = ordered.first else {
            return nil
        }
        for line in ordered.dropFirst() where line.amount > kept.amount {
            kept = line
        }
        return kept
    }

    /// The category a removed split leaves on a transaction of `type`: the kept line's, when it is a live
    /// category of that kind. Otherwise none, so a split whose lines break D64, or whose kept line's category
    /// was deleted, can still be removed, leaving it uncategorised. Saving the transaction with that category
    /// and no lines removes the split; linked refunds take the category in the same save (D33.4).
    public static func keptCategory(
        of splits: [TransactionSplit],
        type: TransactionType,
        in categories: [TransactionCategory],
    ) -> UUID? {
        guard let categoryID = keptLine(of: splits)?.categoryID,
            let category = categories.first(where: { $0.id == categoryID && $0.deletedAt == nil }),
            category.kind.matches(type)
        else {
            return nil
        }
        return categoryID
    }
}

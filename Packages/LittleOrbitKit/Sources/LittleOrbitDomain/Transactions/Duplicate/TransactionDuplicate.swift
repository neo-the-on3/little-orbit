import Foundation

/// The copy rules for Duplicate (D65, QA answer 2 on #34).
public enum TransactionDuplicate {
    /// A new transaction like `transaction`, dated `now` in `timeZoneID`, with copies of its split lines. The
    /// device's current zone becomes the copy's stored zone, and its created and modified stamps are `now`
    /// (D216); the original's date, time and zone aren't kept.
    ///
    /// The copy keeps the type, amount, account or accounts, destination amount, category or split lines (with
    /// their notes), payee, description, notes and tags. It gets a new ID, the default status, and no schedule,
    /// refund link or attachments. A refund can't be duplicated (D65, D117.3): this throws
    /// `refundCannotBeDuplicated`.
    public static func copy(
        of transaction: Transaction,
        splits: [TransactionSplit],
        now: Date,
        timeZoneID: String = TimeZone.current.identifier,
    ) throws -> (transaction: Transaction, splits: [TransactionSplit]) {
        if transaction.isRefund || transaction.refundOfID != nil {
            throw LedgerValidationError.refundCannotBeDuplicated
        }
        let copy = Transaction(
            type: transaction.type,
            amount: transaction.amount,
            date: now,
            timeZoneID: timeZoneID,
            accountID: transaction.accountID,
            categoryID: transaction.categoryID,
            payeeID: transaction.payeeID,
            details: transaction.details,
            note: transaction.note,
            transferAccountID: transaction.transferAccountID,
            destinationAmount: transaction.destinationAmount,
            status: TransactionStatus.newTransactionDefault,
            tagIDs: transaction.tagIDs,
            createdAt: now,
        )
        let lines = splits.filter { $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { line in
                TransactionSplit(
                    transactionID: copy.id,
                    categoryID: line.categoryID,
                    amount: line.amount,
                    note: line.note,
                    sortOrder: line.sortOrder,
                    createdAt: now,
                )
            }
        return (copy, lines)
    }
}

/// Whether Duplicate is offered for a row (D65, D117.2, D117.3).
public enum DuplicateAvailability: Equatable, Sendable {
    case available
    /// Not offered: a refund can't be duplicated, so Duplicate is hidden on it (D117.3, D237.3).
    case disabledForRefund
}

/// The Refund and Duplicate actions a row offers in its swipe, long-press and context menus and through
/// Cmd+R and Cmd+D (D65, D117.2, D117.3).
public struct TransactionActions: Equatable, Sendable {
    /// Refund is offered only for an expense that isn't itself a refund.
    public var canRefund: Bool
    public var duplicate: DuplicateAvailability

    public init(for transaction: Transaction) {
        let isRefund = transaction.isRefund || transaction.refundOfID != nil
        canRefund = transaction.type == .expense && !isRefund
        duplicate = isRefund ? .disabledForRefund : .available
    }

    /// The actions for a selection. Cmd+D and Cmd+R work on exactly one row, so several rows, or none, offer
    /// neither (#31, D65).
    public static func forSelection(_ transactions: [Transaction]) -> TransactionActions? {
        guard transactions.count == 1, let only = transactions.first else {
            return nil
        }
        return TransactionActions(for: only)
    }
}

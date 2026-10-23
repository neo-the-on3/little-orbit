import Foundation

/// What stops the refund form from saving (D33, D35, D65, D97.4).
public enum RefundIssue: Equatable, Sendable {
    case amountMissing
    /// The amount is more than can still be refunded; carries the most that can (D35, QA answer 1).
    case exceedsRefundable(Decimal)
    /// The expense is fully refunded, so Save stays disabled.
    case nothingRefundable
    /// The refund's account isn't in the expense's currency (D33).
    case currencyMismatch
    /// The refund is dated before its expense, whose day this carries (D97.4).
    case dateBeforeOriginal(CalendarDay)
}

/// The refund form's rules for an expense that isn't split (#34, D33, D35, D65, D97.4).
///
/// Refunds of split lines, the Counts on (effective) date and the ledger-level cap aren't here yet; see the
/// pull request for #34.
public enum RefundPlan {
    /// What the live refunds linked to `expenseID` add up to, leaving out `excluding` (the refund being edited).
    public static func refunded(of expenseID: UUID, in transactions: [Transaction], excluding: UUID? = nil) -> Decimal {
        transactions.filter { $0.refundOfID == expenseID && $0.isRefund && $0.deletedAt == nil && $0.id != excluding }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// The most that can still be refunded on `expense`, never below 0.
    public static func refundable(
        for expense: Transaction,
        in transactions: [Transaction],
        excluding: UUID? = nil,
    ) -> Decimal {
        max(0, expense.amount - refunded(of: expense.id, in: transactions, excluding: excluding))
    }

    /// A new refund of `expense`: the remaining amount, dated `now`, in the expense's category, account and payee
    /// (D65, S14, D234.4). The payee is set only when its record still exists, and the description is left
    /// empty. `nil` when Refund isn't offered for it (`TransactionActions.canRefund`) or it's split.
    public static func newRefund(
        of expense: Transaction,
        in snapshot: LedgerSnapshot,
        now: Date,
        timeZoneID: String = TimeZone.current.identifier,
    ) -> Transaction? {
        guard TransactionActions(for: expense).canRefund, snapshot.splitsVisible(for: expense.id).isEmpty else {
            return nil
        }
        let payeeID = expense.payeeID.flatMap { id in snapshot.payeesVisible().contains { $0.id == id } ? id : nil }
        return Transaction(
            type: .income,
            amount: refundable(for: expense, in: snapshot.transactions),
            date: now,
            timeZoneID: timeZoneID,
            accountID: expense.accountID,
            categoryID: expense.categoryID,
            payeeID: payeeID,
            status: TransactionStatus.newTransactionDefault,
            refundOfID: expense.id,
            isRefund: true,
            createdAt: now,
        )
    }

    /// What stops `refund` of `expense` from saving, in the order the form shows them.
    public static func issues(
        of refund: Transaction,
        for expense: Transaction,
        in snapshot: LedgerSnapshot,
    ) -> [RefundIssue] {
        var issues: [RefundIssue] = []
        let limit = refundable(for: expense, in: snapshot.transactions, excluding: refund.id)
        if limit <= 0 {
            issues.append(.nothingRefundable)
        } else if refund.amount <= 0 {
            issues.append(.amountMissing)
        } else if refund.amount > limit {
            issues.append(.exceedsRefundable(limit))
        }
        let currency = { (id: UUID?) in
            snapshot.accounts.first { $0.id == id && $0.deletedAt == nil }?.currencyCode
        }
        if currency(refund.accountID) != currency(expense.accountID) {
            issues.append(.currencyMismatch)
        }
        // Each record on its own day in its own stored zone, an unknown zone reading as UTC (D229.1): the same
        // comparison as Undo's stale check, so the two can't disagree.
        if RefundDating.isOriginal(expense, datedAfter: refund) {
            issues.append(
                .dateBeforeOriginal(TransactionCalendar.ownDay(of: expense.date, timeZoneID: expense.timeZoneID))
            )
        }
        return issues
    }
}

import Foundation

/// A refund as the refund sheet shows it, checked against the ledger as it is now (#34, D33, D35, D65, D97.4,
/// D229.1): its expense, what's already refunded and still refundable, what stops it from saving, and the
/// records the sheet names.
public struct RefundCheck: Equatable, Sendable {
    public var expense: Transaction
    /// The live refunds of the expense, leaving out the one being checked.
    public var refunded: Decimal
    /// The most this refund can be, never below 0.
    public var refundable: Decimal
    /// What stops the refund from saving, in the order the sheet shows them (`RefundPlan.issues`).
    public var issues: [RefundIssue]
    /// Live accounts, categories and payees, for the sheet's names and the account picker.
    public var accounts: [Account]
    public var categories: [TransactionCategory]
    public var payees: [Payee]

    public init(
        expense: Transaction,
        refunded: Decimal,
        refundable: Decimal,
        issues: [RefundIssue],
        accounts: [Account],
        categories: [TransactionCategory],
        payees: [Payee],
    ) {
        self.expense = expense
        self.refunded = refunded
        self.refundable = refundable
        self.issues = issues
        self.accounts = accounts
        self.categories = categories
        self.payees = payees
    }
}

/// A refund save that `RefundPlan` blocks; nothing was written.
public struct RefundBlocked: Error, Equatable, Sendable {
    public var issues: [RefundIssue]

    public init(issues: [RefundIssue]) {
        self.issues = issues
    }
}

/// Recording a refund of an expense, from the iOS refund sheet and the macOS ⌘R sheet (#34, D65).
@MainActor
public protocol RefundTransactionUseCase {
    /// A new refund of the expense, prefilled by `RefundPlan.newRefund` (D65, S14, D234.4) and dated `now` in
    /// `timeZoneID`. `nil` when Refund isn't offered for it: it's gone, not an expense, a refund, or split.
    func newRefund(of expenseID: UUID, now: Date, timeZoneID: String) throws -> Transaction?
    /// `refund` against the ledger as it is now, so the sheet follows changes made in other windows. `nil` when
    /// its expense is gone or can no longer be refunded.
    func check(_ refund: Transaction) throws -> RefundCheck?
    /// Whether the expense is still there and now split, which Schema V1 can't refund (D35.6, D251.1), so the
    /// sheet can say why `check` found nothing.
    func isSplit(_ expenseID: UUID) throws -> Bool
    /// Saves the refund with the payee as typed, all or nothing, and returns the change, so one Undo removes it.
    /// `payeeName` is an existing payee's name, a new name, which creates that payee with the refund (Undo
    /// removes it again, D191.4), or blank for none (D235). Throws `RefundBlocked` when `check` finds issues,
    /// `refundOriginalMissing` when the expense is gone, or the ledger's own error; none of them writes anything.
    func save(_ refund: Transaction, payeeName: String) throws -> TransactionChange
}

@MainActor
public struct DefaultRefundTransactionUseCase: RefundTransactionUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func newRefund(of expenseID: UUID, now: Date, timeZoneID: String) throws -> Transaction? {
        let snapshot = try snapshot()
        guard let expense = snapshot.transactionsVisible().first(where: { $0.id == expenseID }) else {
            return nil
        }
        return RefundPlan.newRefund(of: expense, in: snapshot, now: now, timeZoneID: timeZoneID)
    }

    public func check(_ refund: Transaction) throws -> RefundCheck? {
        let snapshot = try snapshot()
        guard let expenseID = refund.refundOfID,
            let expense = snapshot.transactionsVisible().first(where: { $0.id == expenseID }),
            TransactionActions(for: expense).canRefund,
            snapshot.splitsVisible(for: expense.id).isEmpty
        else {
            return nil
        }
        return RefundCheck(
            expense: expense,
            refunded: RefundPlan.refunded(of: expense.id, in: snapshot.transactions, excluding: refund.id),
            refundable: RefundPlan.refundable(for: expense, in: snapshot.transactions, excluding: refund.id),
            issues: RefundPlan.issues(of: refund, for: expense, in: snapshot),
            accounts: snapshot.accountsVisible(),
            categories: snapshot.categoriesVisible(),
            payees: snapshot.payeesVisible(),
        )
    }

    public func isSplit(_ expenseID: UUID) throws -> Bool {
        let snapshot = try snapshot()
        return snapshot.transactionsVisible().contains { $0.id == expenseID }
            && !snapshot.splitsVisible(for: expenseID).isEmpty
    }

    public func save(_ refund: Transaction, payeeName: String) throws -> TransactionChange {
        try repository.atomically {
            guard let check = try check(refund) else {
                throw LedgerValidationError.refundOriginalMissing
            }
            guard check.issues.isEmpty else {
                throw RefundBlocked(issues: check.issues)
            }
            let payees = DefaultSaveTransactionsUseCase(repository: repository)
            let resolved = try payees.resolvePayee(named: payeeName, createdAt: refund.createdAt)
            var refund = refund
            refund.payeeID = resolved?.payee.id
            try repository.saveTransaction(refund)
            let created = resolved.flatMap { $0.isNew ? [$0.payee] : nil } ?? []
            return .saved(.added([refund.id]), creating: try PayeeCleanup(repository: repository).stored(created))
        }
    }

    private func snapshot() throws -> LedgerSnapshot {
        LedgerSnapshot(
            accounts: try repository.accounts(),
            transactions: try repository.transactions(),
            categories: try repository.categories(),
            payees: try repository.payees(),
            splits: try repository.splits(for: nil),
        )
    }
}

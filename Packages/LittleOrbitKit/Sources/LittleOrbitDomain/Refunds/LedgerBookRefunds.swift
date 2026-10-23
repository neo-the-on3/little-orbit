import Foundation

/// The refund rules every save, delete and restore goes through (#55; D19, D33, D35).
///
/// A refund is an income with `isRefund` set. While linked (`refundOfID` set) it points to a live, unsplit
/// expense, uses that expense's category and currency, and the refunds of one expense add up to no more than
/// its amount. An unlinked refund ('Refund (original deleted)') is valid on its own, with an expense category
/// or none; the in-app editor can't create one (`DefaultSaveTransactionsUseCase`), but deleting an expense,
/// CSV import and sync can (D35.2).
extension LedgerBook {
    /// The live refunds linked to `originalID`, in stored order.
    public static func linkedRefunds(of originalID: UUID, in snapshot: LedgerSnapshot) -> [Transaction] {
        snapshot.transactions.filter { $0.refundOfID == originalID && $0.deletedAt == nil }
    }

    /// What the live refunds linked to `originalID` add up to, leaving out `excluding`.
    public static func refundedAmount(
        of originalID: UUID,
        in snapshot: LedgerSnapshot,
        excluding: UUID? = nil,
    ) -> Decimal {
        linkedRefunds(of: originalID, in: snapshot)
            .filter { $0.id != excluding }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Checks a refund against its original. `validate` has already rejected a link without `isRefund` (D33.1).
    static func validateRefund(_ transaction: Transaction, in snapshot: LedgerSnapshot) throws {
        guard transaction.isRefund else {
            return
        }
        if transaction.type != .income {
            throw LedgerValidationError.refundMustBeIncome
        }
        guard let originalID = transaction.refundOfID else {
            return
        }
        guard
            originalID != transaction.id,
            let original = snapshot.transactions.first(where: { $0.id == originalID && $0.deletedAt == nil })
        else {
            throw LedgerValidationError.refundOriginalMissing
        }
        if original.type != .expense || original.isRefund {
            throw LedgerValidationError.refundOriginalNotExpense
        }
        if !snapshot.splitsVisible(for: original.id).isEmpty {
            throw LedgerValidationError.refundOriginalIsSplit
        }
        if transaction.categoryID != original.categoryID {
            throw LedgerValidationError.refundCategoryMismatch
        }
        if currency(of: transaction, in: snapshot) != currency(of: original, in: snapshot) {
            throw LedgerValidationError.refundCurrencyMismatch
        }
        let refunded = refundedAmount(of: original.id, in: snapshot, excluding: transaction.id)
        if refunded + transaction.amount > original.amount {
            throw LedgerValidationError.refundsExceedOriginal
        }
    }

    /// Checks `transaction` against the refunds already linked to it: it stays an expense, in their currency,
    /// and its amount covers them (D33.5, D35.1).
    static func validateOriginal(_ transaction: Transaction, in snapshot: LedgerSnapshot) throws {
        guard transaction.deletedAt == nil else {
            return
        }
        let refunds = linkedRefunds(of: transaction.id, in: snapshot).filter { $0.id != transaction.id }
        guard !refunds.isEmpty else {
            return
        }
        if transaction.type != .expense || transaction.isRefund {
            throw LedgerValidationError.originalHasRefunds
        }
        let currency = currency(of: transaction, in: snapshot)
        if refunds.contains(where: { self.currency(of: $0, in: snapshot) != currency }) {
            throw LedgerValidationError.refundCurrencyMismatch
        }
        let refunded = refunds.reduce(Decimal(0)) { $0 + $1.amount }
        if transaction.amount < refunded {
            throw LedgerValidationError.amountBelowRefunds(refunded)
        }
    }

    /// After `original` is saved: its linked refunds take its category in the same change (D33.4), and if it
    /// was saved as deleted, they're unlinked as if it had been deleted (D19).
    static func applyingOriginal(_ original: Transaction, to snapshot: inout LedgerSnapshot, now: Date) {
        if original.deletedAt != nil {
            unlinkRefunds(of: [original.id], in: &snapshot, now: now)
            return
        }
        guard original.type == .expense else {
            return
        }
        for index in snapshot.transactions.indices {
            let refund = snapshot.transactions[index]
            guard refund.refundOfID == original.id, refund.deletedAt == nil,
                refund.categoryID != original.categoryID
            else {
                continue
            }
            snapshot.transactions[index].categoryID = original.categoryID
            snapshot.transactions[index].updatedAt = now
        }
    }

    /// Unlinks every live refund of these originals. Each keeps `isRefund` and its category, so it reads
    /// 'Refund (original deleted)' (D19).
    static func unlinkRefunds(of originalIDs: Set<UUID>, in snapshot: inout LedgerSnapshot, now: Date) {
        guard !originalIDs.isEmpty else {
            return
        }
        for index in snapshot.transactions.indices {
            guard let originalID = snapshot.transactions[index].refundOfID, originalIDs.contains(originalID),
                snapshot.transactions[index].deletedAt == nil
            else {
                continue
            }
            snapshot.transactions[index].refundOfID = nil
            snapshot.transactions[index].updatedAt = now
        }
    }

    /// The currency of the transaction's live account, or `nil` without one.
    private static func currency(of transaction: Transaction, in snapshot: LedgerSnapshot) -> String? {
        transaction.accountID.flatMap { activeAccount($0, in: snapshot) }?.currencyCode
    }
}

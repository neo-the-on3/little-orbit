import Foundation

/// Whether Undo of a delete can bring back the refunds it removed while they were linked, when their expense
/// changed since in another window or outside any window (D224; Tech Architect's B1 on #125). Undo of a
/// refund delete, a bulk delete and an account delete all use it.
///
/// - The expense is gone: the refund comes back unlinked, as 'Refund (original deleted)', the same as if it
///   had still been there when the expense was deleted (D224.1). Not stale.
/// - The expense exists but can't take the refund back: the whole step is stale, 'Can't Undo' (D224.2–D224.4).
/// - A category change isn't a reason: the refund comes back in the expense's current category (D33.4).
@MainActor
struct RefundRestoreCheck {
    let repository: any LedgerRepository

    /// The live expenses that can no longer take back a refund among `items`, which the same step doesn't
    /// restore. One is enough to make the step stale.
    func blockingOriginals(
        of items: [RemovedTransaction],
        restoring accounts: [Account] = [],
        current: [UUID: Transaction],
    ) throws -> [UUID] {
        let restored = Set(items.map(\.transaction.id))
        var returning: [UUID: [Transaction]] = [:]
        for item in items {
            if let originalID = item.transaction.refundOfID, !restored.contains(originalID),
                current[originalID] != nil
            {
                returning[originalID, default: []].append(item.transaction)
            }
        }
        guard !returning.isEmpty else {
            return []
        }
        // One pass over each source, so a bulk Undo stays linear in the size of the ledger.
        var currencies: [UUID: String] = [:]
        for account in try repository.accounts() + accounts where account.deletedAt == nil {
            currencies[account.id] = account.currencyCode
        }
        let split = Set(try repository.splits(for: nil).compactMap(\.transactionID))
        var refunded: [UUID: Decimal] = [:]
        for transaction in current.values {
            if let originalID = transaction.refundOfID, returning[originalID] != nil {
                refunded[originalID, default: 0] += transaction.amount
            }
        }
        var blocking: [UUID] = []
        for (originalID, refunds) in returning {
            guard let original = current[originalID] else {
                continue
            }
            let fits = Fit(
                original: original,
                isSplit: split.contains(originalID),
                refunded: refunded[originalID] ?? 0,
                currencies: currencies,
            )
            if !fits.canTake(refunds) {
                blocking.append(originalID)
            }
        }
        return blocking.sorted { $0.uuidString < $1.uuidString }
    }
}

/// D224.2 and D224.3 on Schema V1, for one live expense.
private struct Fit {
    let original: Transaction
    let isSplit: Bool
    /// What the refunds linked to it now come to.
    let refunded: Decimal
    let currencies: [UUID: String]

    /// Still an unsplit expense, in the refunds' currency, not dated after any of them (`RefundDating`), with
    /// room under its amount for all of them next to the refunds it has now (D33.2).
    func canTake(_ refunds: [Transaction]) -> Bool {
        guard original.type == .expense, !original.isRefund, !isSplit else {
            return false
        }
        let currency = original.accountID.flatMap { currencies[$0] }
        for refund in refunds {
            if refund.accountID.flatMap({ currencies[$0] }) != currency {
                return false
            }
            if RefundDating.isOriginal(original, datedAfter: refund) {
                return false
            }
        }
        return refunded + refunds.reduce(Decimal(0)) { $0 + $1.amount } <= original.amount
    }
}

import Foundation

/// Deletes transactions or a whole account, keeping copies so Undo can put everything back. Both the account
/// delete (`DeleteAccountUseCase`) and Redo of a restored account use it, so there is one way to delete an
/// account (#93). Callers run it inside `atomically`.
///
/// Known gap (sync, #21): `transactions()` returns only live rows, so an account's soft-deleted transactions
/// (tombstones), which `LedgerBook.deletingAccount` also removes, aren't kept and don't come back on Undo.
@MainActor
struct LedgerRemoval {
    let repository: any LedgerRepository

    /// Deletes these transactions with their attachments and splits. Ids that are gone are skipped. Each
    /// deleted expense's refunds are unlinked (D19); the result records which, for Undo.
    func transactions(ids: [UUID]) throws -> [RemovedTransaction] {
        let all = try repository.transactions()
        var live = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        // Indexed once, so a bulk delete doesn't scan the ledger for each expense's refunds.
        var refundsByOriginal: [UUID: [UUID]] = [:]
        for transaction in all {
            if let originalID = transaction.refundOfID {
                refundsByOriginal[originalID, default: []].append(transaction.id)
            }
        }
        var removed: [RemovedTransaction] = []
        for id in ids {
            guard let transaction = live.removeValue(forKey: id) else {
                continue
            }
            let refundIDs = (refundsByOriginal.removeValue(forKey: id) ?? []).filter { live[$0] != nil }
            removed.append(
                RemovedTransaction(
                    transaction: transaction,
                    attachments: try repository.attachments(for: id),
                    splits: try repository.splits(for: id),
                    unlinkedRefundIDs: refundIDs,
                )
            )
            try repository.deleteTransaction(id: id)
            // As the delete left them, for a refund this same change deletes next.
            for refundID in refundIDs {
                live[refundID]?.refundOfID = nil
            }
        }
        return removed
    }

    /// Deletes the account with its transactions and transfers in or out. Throws
    /// `AccountUseCaseError.accountNotFound` if it's gone.
    func account(_ id: UUID) throws -> RemovedAccount {
        guard let account = try repository.accounts().first(where: { $0.id == id }) else {
            throw AccountUseCaseError.accountNotFound
        }
        let ids = try repository.transactions()
            .filter { $0.accountID == id || $0.transferAccountID == id }
            .map(\.id)
        let transactions = try transactions(ids: ids)
        try repository.deleteAccount(id: id)
        return RemovedAccount(account: account, transactions: transactions)
    }
}

import Foundation

/// `PayeeCleanup`'s rules on a ledger value, for an Undo or Redo built off the main actor (#285). Each one is the
/// method of the same name step for step, with the store's reads and writes as reads and `LedgerBook` changes of
/// `snapshot`; `TransactionRevertBatchTests` checks the two give the same ledger.
extension PayeeCleanup {
    /// `stored(_:)`: these payees as `snapshot` holds them; any that are gone are left out.
    nonisolated static func stored(_ payees: [Payee], in snapshot: LedgerSnapshot) -> [Payee] {
        let current = snapshot.payeesVisible()
        return payees.compactMap { payee in current.first { $0.id == payee.id } }
    }

    /// `removeUnused(_:)`: removes each payee nothing uses and nothing has touched since its save created it
    /// (D191.4a, D362, D384.7), and returns the ones removed, as they were, for Redo.
    nonisolated static func removingUnused(
        _ payees: [Payee],
        from snapshot: inout LedgerSnapshot,
        now date: Date,
    ) throws -> [Payee] {
        var removed: [Payee] = []
        for created in payees {
            guard let now = snapshot.payeesVisible().first(where: { $0.id == created.id }),
                now.isUntouched(since: created),
                snapshot.payeeReferenceCount(now.id) == 0
            else {
                continue
            }
            snapshot = try LedgerBook.deletingPayee(id: now.id, in: snapshot, now: date)
            removed.append(now)
        }
        return removed
    }

    /// `restore(_:for:)`: puts these payees back with the same IDs before Redo reapplies `change` (D191.4a.3),
    /// or points the change at a live payee with the same name, and returns the ones put back with the change.
    nonisolated static func restoring(
        _ payees: [Payee],
        for change: TransactionChange,
        in snapshot: inout LedgerSnapshot,
        now: Date,
    ) throws -> ([Payee], TransactionChange) {
        let categories = Set(snapshot.categoriesVisible().map(\.id))
        var restored: [Payee] = []
        var change = change
        for removed in payees {
            let live = snapshot.payeesVisible()
            if live.contains(where: { $0.id == removed.id }) {
                continue
            }
            if let twin = live.first(where: { $0.isLive(named: removed.name) }) {
                change = change.replacingPayee(removed.id, with: twin.id)
                continue
            }
            var payee = removed
            if let category = payee.defaultCategoryID, !categories.contains(category) {
                payee.defaultCategoryID = nil
            }
            snapshot = try LedgerBook.savingPayee(payee, in: snapshot, now: now)
            restored.append(snapshot.payeesVisible().first { $0.id == payee.id } ?? payee)
        }
        return (restored, change)
    }
}

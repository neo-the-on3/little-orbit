import Foundation

/// The payees that come and go with a change (D191.4). Callers run it inside `atomically`, in the same save as
/// the change, so the count and the delete see the change's own writes.
@MainActor
struct PayeeCleanup {
    let repository: any LedgerRepository

    /// Removes each payee that nothing uses any more and nothing has touched since its save created it
    /// (`Payee.isUntouched(since:)`, D362, D384.7). Any other payee stays, silently, as it is now (D191.4a).
    /// Returns the ones removed, as they were, for Redo.
    func removeUnused(_ payees: [Payee]) throws -> [Payee] {
        var removed: [Payee] = []
        for created in payees {
            guard let now = try repository.payees().first(where: { $0.id == created.id }),
                now.isUntouched(since: created),
                try repository.payeeReferenceCount(now.id) == 0
            else {
                continue
            }
            try repository.deletePayee(id: now.id)
            removed.append(now)
        }
        return removed
    }

    /// These payees as stored now; any that are gone are left out.
    func stored(_ payees: [Payee]) throws -> [Payee] {
        let current = try repository.payees()
        return payees.compactMap { payee in current.first { $0.id == payee.id } }
    }

    /// Puts these payees back with the same IDs before Redo reapplies `change` (D191.4a.3), and returns the
    /// ones put back with the change to reapply. A default category deleted since is left out. If another
    /// window has since added a payee with the same name, the change uses that one instead, so there are
    /// never two.
    func restore(_ payees: [Payee], for change: TransactionChange) throws -> ([Payee], TransactionChange) {
        let categories = Set(try repository.categories().map(\.id))
        var restored: [Payee] = []
        var change = change
        for removed in payees {
            let live = try repository.payees()
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
            try repository.savePayee(payee)
            restored.append(try repository.payees().first { $0.id == payee.id } ?? payee)
        }
        return (restored, change)
    }
}

extension Payee {
    /// The one rule for "a payee with this name": live, and the same name ignoring case. `resolvePayee` and
    /// Redo's same-name check both use it, so they can't drift apart.
    func isLive(named name: String) -> Bool {
        deletedAt == nil && self.name.compare(name, options: [.caseInsensitive]) == .orderedSame
    }
}

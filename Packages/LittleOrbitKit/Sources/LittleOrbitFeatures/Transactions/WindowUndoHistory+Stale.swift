import Foundation
import LittleOrbitDomain

// MARK: Stale steps

extension WindowUndoHistory {
    /// "Corner Bakery has changed since then. Nothing was changed." (D187.5, X1–X6). It never names a cause:
    /// the check is by value, so a change from another window or from outside any window reads the same (D228).
    func staleMessage(_ reason: StaleReason, _ step: Step) -> String {
        switch reason {
        case .accountDeleted(let ids):
            let name = (step.impact.accounts + [step.account].compactMap(\.self))
                .first { ids.contains($0.id) }?
                .name
            return StaleText.deleted(name ?? StaleText.theAccount)
        case .deleted(let ids):
            return staleRecords(ids, step, deleted: true)
        case .changed(let ids):
            return staleRecords(ids, step, deleted: false)
        case .changedAndDeleted(let changed, let deleted):
            return StaleText.changedOrDeleted(changed.count + deleted.count)
        }
    }

    private func staleRecords(_ ids: [UUID], _ step: Step, deleted: Bool) -> String {
        // One stale record is named, even in a bulk step; more are counted (D189.2).
        if ids.count > 1 {
            return StaleText.changedOrDeleted(ids.count)
        }
        let name: String
        if let id = ids.first, let transaction = version(of: id, in: step) {
            name = StaleText.name(of: transaction, payees: (try? loadLedger.ledger().payees) ?? [])
        } else if let account = step.account {
            name = account.name
        } else {
            name = StaleText.theTransaction
        }
        return deleted ? StaleText.deleted(name) : StaleText.changed(name)
    }

    /// A version of the transaction the step knows, for its name.
    private func version(of id: UUID, in step: Step) -> Transaction? {
        if let left = step.outcome.transactions[id] {
            return left
        }
        switch step.change.core {
        case .removed(let items): return items.first { $0.transaction.id == id }?.transaction
        case .replaced(let versions): return versions.first { $0.id == id }
        case .removedAccount(let removed): return removed.transactions.first { $0.transaction.id == id }?.transaction
        case .added, .addedAccount, .createdPayees, .removedPayees: return nil
        }
    }
}

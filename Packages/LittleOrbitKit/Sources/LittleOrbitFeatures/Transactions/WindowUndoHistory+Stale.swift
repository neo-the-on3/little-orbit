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
        // A scheduled item step names its item as the step did (D351.1, D228).
        case .scheduledItemChanged:
            return StaleText.changed(step.subject ?? StaleText.theTransaction)
        case .scheduledItemDeleted:
            return StaleText.deleted(step.subject ?? StaleText.theTransaction)
        }
    }

    private func staleRecords(_ ids: [UUID], _ step: Step, deleted: Bool) -> String {
        // One stale record is named, even in a bulk step; more are counted (D189.2).
        if ids.count > 1 {
            return StaleText.changedOrDeleted(ids.count)
        }
        guard let id = ids.first else {
            // No transaction to name: a restored account that is back in the ledger.
            let name = step.account?.name ?? StaleText.theTransaction
            return deleted ? StaleText.deleted(name) : StaleText.changed(name)
        }
        // A record the step holds is named as the step left it (D228), even when it's in the step's account. A
        // record the step doesn't hold but is now in that account changed the account's contents, so the account
        // is named. Any other record the step doesn't hold, such as the expense a refund delete would link again
        // (#128 S23), is named as the ledger has it now, as its row is (D228.4).
        let ledger = try? loadLedger.ledger()
        let name: String
        if let held = version(of: id, in: step) {
            name = StaleText.name(of: held, payees: ledger?.payees ?? [])
        } else if let current = deleted ? nil : ledger?.transactions.first(where: { $0.id == id }) {
            if let account = step.account, current.accountID == account.id || current.transferAccountID == account.id {
                name = account.name
            } else {
                name = StaleText.name(of: current, payees: ledger?.payees ?? [])
            }
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
        case .added, .addedAccount, .createdPayees, .removedPayees, .savedScheduledItem, .revertedScheduledItemSave:
            return nil
        }
    }
}

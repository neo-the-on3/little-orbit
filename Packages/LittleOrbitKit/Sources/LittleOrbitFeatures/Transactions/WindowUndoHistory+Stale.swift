import Foundation
import LittleOrbitDomain

// MARK: Stale steps

extension WindowUndoHistory {
    /// "Corner Bakery has changed since then. Nothing was changed." (D187.5, X1–X6). It never names a cause:
    /// the check is by value, so a change from another window or from outside any window reads the same (D228).
    /// A step that would put back a deleted or merged-away category or payee names that record instead, with
    /// the same "has been deleted" message (D306.1 as amended).
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
        case .referenceRemoved(let ids, let removed):
            // One transaction: the existing D228 message names the removed category or payee, the first one if
            // it lost both (D306.1 as amended). More are counted, as any bulk step is (D189.2). A record no one
            // can name keeps the step's own wording.
            if ids.count == 1, let name = removedName(removed, step) {
                return StaleText.deleted(name)
            }
            return staleRecords(ids, step, deleted: false)
        }
    }

    /// The first removed record with a name: as the store still has it, else as the step kept it.
    private func removedName(_ removed: [RemovedReference], _ step: Step) -> String? {
        let ids = removed.map(\.id)
        let stored = try? loadLedger.recordNames(
            categoryIDs: Set(removed.compactMap(\.categoryID)),
            payeeIDs: Set(removed.compactMap(\.payeeID)),
        )
        return ids.lazy.compactMap { stored?[$0] ?? step.recordNames[$0] }.first
    }

    /// Keeps the names of the categories and payees the step's next Undo or Redo would put back (D306.1). It
    /// reads only those names, never the whole ledger (NB8). A name already kept stays when the store no longer
    /// has the record, and follows a rename when it does.
    func captureRecordNames(for step: Step) {
        var versions = Array(step.outcome.transactions.values)
        var splits: [TransactionSplit] = []
        switch step.change.core {
        case .removed(let items):
            versions += items.map(\.transaction)
            splits += items.flatMap(\.splits)
        case .replaced(let previous):
            versions += previous
        case .removedAccount(let removed):
            versions += removed.transactions.map(\.transaction)
            splits += removed.transactions.flatMap(\.splits)
        case .added, .addedAccount, .createdPayees, .removedPayees:
            break
        }
        let categoryIDs = Set(versions.compactMap(\.categoryID) + splits.compactMap(\.categoryID))
        let payeeIDs = Set(versions.compactMap(\.payeeID))
        guard !categoryIDs.isEmpty || !payeeIDs.isEmpty,
            let names = try? loadLedger.recordNames(categoryIDs: categoryIDs, payeeIDs: payeeIDs)
        else {
            return
        }
        step.recordNames.merge(names) { _, current in current }
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
        case .added, .addedAccount, .createdPayees, .removedPayees: return nil
        }
    }
}

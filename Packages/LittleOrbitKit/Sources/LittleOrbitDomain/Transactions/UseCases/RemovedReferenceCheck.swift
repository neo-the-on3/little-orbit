import Foundation

/// Finds the transactions a revert would write back with a category or payee that's gone: deleted, or merged
/// away, in another window or outside any window (D287.4). A category merge or delete and a payee merge aren't
/// undoable (D287.2), so such a step is stale (D187.5) rather than a write the ledger refuses (D191.2).
///
/// The check is by value, on what reverting would write, so it agrees with `revertEdits`: a field the step
/// didn't touch keeps its current value, which is always live, and isn't checked. An archived category or
/// payee isn't gone (D295.7). A payee the revert itself puts back (Redo, D191.4a.3) isn't gone either.
@MainActor
struct RemovedReferenceCheck {
    let repository: any LedgerRepository

    /// The step's transactions that would point at a removed category or payee, in the change's order, and
    /// those records once each: per transaction its category, then its split lines' categories, then its payee.
    func transactions(
        _ change: TransactionChange,
        expecting outcome: ChangeOutcome,
        current: [UUID: Transaction],
    ) throws -> (transactionIDs: [UUID], removed: [RemovedReference]) {
        let written = Self.written(change, outcome: outcome, current: current)
        guard !written.versions.isEmpty else {
            return ([], [])
        }
        let categories = Set(try repository.categories().filter { $0.deletedAt == nil }.map(\.id))
        let payees = Set(try repository.payees().filter { $0.deletedAt == nil }.map(\.id))
            .union(written.restoredPayees)
        var orphaned: [UUID] = []
        var removed: [RemovedReference] = []
        for version in written.versions {
            let usedCategories =
                [version.transaction.categoryID].compactMap(\.self)
                + version.splits.compactMap(\.categoryID)
            let usedPayees = [version.transaction.payeeID].compactMap(\.self)
            let gone =
                usedCategories.filter { !categories.contains($0) }.map(RemovedReference.category)
                + usedPayees.filter { !payees.contains($0) }.map(RemovedReference.payee)
            guard !gone.isEmpty else {
                continue
            }
            if !orphaned.contains(version.transaction.id) {
                orphaned.append(version.transaction.id)
            }
            for reference in gone where !removed.contains(reference) {
                removed.append(reference)
            }
        }
        return (orphaned, removed)
    }

    /// One transaction as the revert would write it, with the split lines it would put back.
    fileprivate struct Version {
        var transaction: Transaction
        var splits: [TransactionSplit] = []
    }

    /// What the revert writes, and the payees it puts back first.
    private static func written(
        _ change: TransactionChange,
        outcome: ChangeOutcome,
        current: [UUID: Transaction],
    ) -> (versions: [Version], restoredPayees: Set<UUID>) {
        switch change {
        case .createdPayees(_, let inner):
            return written(inner, outcome: outcome, current: current)
        case .removedPayees(let payees, let inner):
            let result = written(inner, outcome: outcome, current: current)
            return (result.versions, result.restoredPayees.union(payees.map(\.id)))
        case .removed(let items):
            return (items.map(Version.init), [])
        case .removedAccount(let removed):
            return (removed.transactions.map(Version.init), [])
        case .replaced(let previous):
            return (previous.compactMap { edited(from: $0, outcome: outcome, current: current) }, [])
        case .added, .addedAccount:
            return ([], [])
        }
    }

    /// The version `revertEdits` writes: the earlier version as it was if nothing else changed it, or the
    /// current one with the fields the step touched put back.
    private static func edited(
        from old: Transaction,
        outcome: ChangeOutcome,
        current: [UUID: Transaction],
    ) -> Version? {
        guard let now = current[old.id] else {
            return nil
        }
        if now == outcome.transactions[old.id] {
            return Version(transaction: old)
        }
        var merged = now
        for field in outcome.touchedFields[old.id] ?? Set(TransactionField.allCases) {
            field.copy(from: old, into: &merged)
        }
        return Version(transaction: merged)
    }
}

extension RemovedReferenceCheck.Version {
    fileprivate init(_ item: RemovedTransaction) {
        self.init(transaction: item.transaction, splits: item.splits.filter { $0.deletedAt == nil })
    }
}

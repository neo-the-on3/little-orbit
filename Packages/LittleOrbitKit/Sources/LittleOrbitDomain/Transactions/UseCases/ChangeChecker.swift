import Foundation

/// Reads what a change left and checks it against the ledger, by value (D187.5). Callers that write run it
/// inside `atomically`, so nothing can change between the check and the write.
@MainActor
struct ChangeChecker {
    let repository: any LedgerRepository

    func outcome(of change: TransactionChange) throws -> ChangeOutcome {
        let current = Dictionary(uniqueKeysWithValues: try repository.transactions().map { ($0.id, $0) })
        var outcome = ChangeOutcome()
        // The payees a save created have their own, silent rule (D191.4a); the check is on the change.
        switch change.core {
        case .removed(let items):
            outcome.removedTransactionIDs = Set(items.map(\.transaction.id))
            outcome.accountIDs = Self.accounts(of: items.map(\.transaction))
        case .added(let ids):
            for id in ids {
                outcome.keep(current[id], touching: Set(TransactionField.allCases))
            }
        case .replaced(let previous):
            for old in previous {
                outcome.keep(
                    current[old.id],
                    touching: current[old.id].map { TransactionField.changed(from: old, to: $0) },
                )
            }
            outcome.accountIDs = Self.accounts(of: previous)
        case .removedAccount(let removed):
            outcome.removedAccountIDs = [removed.account.id]
            outcome.removedTransactionIDs = Set(removed.transactions.map(\.transaction.id))
            outcome.accountIDs = Self.accounts(of: removed.transactions.map(\.transaction))
                .subtracting([removed.account.id])
        case .createdPayees, .removedPayees:
            break
        case .addedAccount(let id):
            outcome.accountIDs = [id]
            let contents = current.values.filter { $0.accountID == id || $0.transferAccountID == id }
            outcome.accountContents = [id: Set(contents.map(\.id))]
            for transaction in contents {
                outcome.keep(transaction, touching: Set(TransactionField.allCases))
            }
        }
        return outcome
    }

    func check(_ change: TransactionChange, expecting outcome: ChangeOutcome) throws -> ChangeCheck {
        let current = Dictionary(uniqueKeysWithValues: try repository.transactions().map { ($0.id, $0) })
        let live = Set(try repository.accounts().filter { $0.deletedAt == nil }.map(\.id))
        let order = Self.order(change, outcome)

        let goneAccounts = outcome.accountIDs.subtracting(live)
        if !goneAccounts.isEmpty {
            return .stale(.accountDeleted(goneAccounts.sorted { $0.uuidString < $1.uuidString }))
        }
        let missing = order.filter { outcome.transactions[$0] != nil && current[$0] == nil }
        if !missing.isEmpty {
            let accounts = Self.accounts(of: missing.compactMap { outcome.transactions[$0] }).subtracting(live)
            if !accounts.isEmpty {
                return .stale(.accountDeleted(accounts.sorted { $0.uuidString < $1.uuidString }))
            }
        }
        let changed = order.filter { id in
            if outcome.removedTransactionIDs.contains(id) {
                return current[id] != nil
            }
            guard let left = outcome.transactions[id], let now = current[id] else {
                return false
            }
            return !(outcome.touchedFields[id] ?? []).allSatisfy { $0.matches(left, now) }
        }
        let added = outcome.accountContents.flatMap { accountID, ids in
            current.values
                .filter { ($0.accountID == accountID || $0.transferAccountID == accountID) && !ids.contains($0.id) }
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
        }
        let altered = changed + added
        if !missing.isEmpty {
            // A bulk step can have both; the caller counts them together (D189.2).
            return .stale(altered.isEmpty ? .deleted(missing) : .changedAndDeleted(changed: altered, deleted: missing))
        }
        if !altered.isEmpty || !outcome.removedAccountIDs.isDisjoint(with: live) {
            return .stale(.changed(altered))
        }
        return .current
    }

    /// Every transaction the check looks at, in the change's own order first.
    private static func order(_ change: TransactionChange, _ outcome: ChangeOutcome) -> [UUID] {
        var ids = change.transactionIDs
        let rest = Set(outcome.transactions.keys).union(outcome.removedTransactionIDs).subtracting(ids)
        ids += rest.sorted { $0.uuidString < $1.uuidString }
        return ids
    }

    private static func accounts(of transactions: [Transaction]) -> Set<UUID> {
        Set(transactions.flatMap { [$0.accountID, $0.transferAccountID].compactMap(\.self) })
    }
}

extension ChangeOutcome {
    fileprivate mutating func keep(_ transaction: Transaction?, touching fields: Set<TransactionField>?) {
        guard let transaction else {
            return
        }
        transactions[transaction.id] = transaction
        touchedFields[transaction.id] = fields ?? []
    }
}

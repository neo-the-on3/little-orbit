import Foundation

// The transaction use cases (#23). View models depend only on these protocols, injected through their
// initializers; the `Default…` implementations hold the logic and depend on `LedgerRepository`.

/// The transaction read model: live accounts, transactions, categories and payees.
public struct TransactionLedger: Equatable, Sendable {
    public var accounts: [Account]
    public var transactions: [Transaction]
    public var categories: [TransactionCategory]
    public var payees: [Payee]

    public init(
        accounts: [Account] = [],
        transactions: [Transaction] = [],
        categories: [TransactionCategory] = [],
        payees: [Payee] = [],
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.categories = categories
        self.payees = payees
    }
}

/// One account's history page.
public struct AccountHistoryPage: Equatable, Sendable {
    public var account: Account
    public var history: AccountHistory
    /// The records a history entry refers to: the other account of a transfer, categories and payees.
    public var ledger: TransactionLedger

    public init(account: Account, history: AccountHistory, ledger: TransactionLedger) {
        self.account = account
        self.history = history
        self.ledger = ledger
    }
}

@MainActor
public protocol LoadTransactionLedgerUseCase {
    func ledger() throws -> TransactionLedger
    /// The same, for entering transactions: seeds the default categories first if there are none.
    func ledgerForEntry() throws -> TransactionLedger
}

@MainActor
public protocol AccountHistoryUseCase {
    /// The account's history as of `today`, or `nil` when the account is gone.
    func history(of accountID: UUID, today: CalendarDay) throws -> AccountHistoryPage?
}

@MainActor
public protocol SaveTransactionsUseCase {
    /// Saves new or edited transactions, all or none, and returns the revertible change: `.added` for new
    /// ones, `.replaced` with the stored versions for edits.
    func save(_ transactions: [Transaction]) throws -> TransactionChange
    /// The payee with this name (case-insensitive), saving a new one if there is none. `nil` for a blank name.
    func resolvePayee(named name: String, createdAt: Date) throws -> Payee?
}

@MainActor
public protocol TransactionChangesUseCase {
    /// Deletes the transactions with their attachments and splits, all or none, keeping copies for Undo (D19).
    func remove(ids: [UUID]) throws -> TransactionChange
    /// What `change` left in the ledger, read right after it was made or reverted, for the stale check.
    func outcome(of change: TransactionChange) throws -> ChangeOutcome
    /// Whether the ledger still holds what `change` left, compared by value on the fields it touched (D187.5).
    func check(_ change: TransactionChange, expecting outcome: ChangeOutcome) throws -> ChangeCheck
    /// Reverts the change, all or none, if `check` finds it current, and returns its inverse, for Redo, with
    /// that inverse's outcome. A stale change writes nothing. Fields the change didn't touch keep the values
    /// another window gave them.
    func revert(_ change: TransactionChange, expecting outcome: ChangeOutcome) throws -> RevertResult
    /// The accounts, transactions and transfers the change touches, before and after it (D166.3).
    func impact(of change: TransactionChange) throws -> ChangeImpact
}

/// The transaction use cases as one value, for the composition root.
@MainActor
public struct TransactionUseCases {
    public var loadLedger: any LoadTransactionLedgerUseCase
    public var accountHistory: any AccountHistoryUseCase
    public var saveTransactions: any SaveTransactionsUseCase
    public var changes: any TransactionChangesUseCase

    public init(
        loadLedger: any LoadTransactionLedgerUseCase,
        accountHistory: any AccountHistoryUseCase,
        saveTransactions: any SaveTransactionsUseCase,
        changes: any TransactionChangesUseCase,
    ) {
        self.loadLedger = loadLedger
        self.accountHistory = accountHistory
        self.saveTransactions = saveTransactions
        self.changes = changes
    }

    /// The default implementations over one repository.
    public init(repository: any LedgerRepository) {
        self.init(
            loadLedger: DefaultLoadTransactionLedgerUseCase(repository: repository),
            accountHistory: DefaultAccountHistoryUseCase(repository: repository),
            saveTransactions: DefaultSaveTransactionsUseCase(repository: repository),
            changes: DefaultTransactionChangesUseCase(repository: repository),
        )
    }
}

// MARK: - Implementations

@MainActor
public struct DefaultLoadTransactionLedgerUseCase: LoadTransactionLedgerUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func ledger() throws -> TransactionLedger {
        TransactionLedger(
            accounts: try repository.accounts().filter { $0.deletedAt == nil },
            transactions: try repository.transactions(),
            categories: try repository.categories(),
            payees: try repository.payees(),
        )
    }

    public func ledgerForEntry() throws -> TransactionLedger {
        if try repository.categories().isEmpty {
            try repository.seedDefaultCategories()
        }
        return try ledger()
    }
}

@MainActor
public struct DefaultAccountHistoryUseCase: AccountHistoryUseCase {
    private let ledger: DefaultLoadTransactionLedgerUseCase
    private let build = BuildAccountHistory()

    public init(repository: any LedgerRepository) {
        self.ledger = DefaultLoadTransactionLedgerUseCase(repository: repository)
    }

    public func history(of accountID: UUID, today: CalendarDay) throws -> AccountHistoryPage? {
        let contents = try ledger.ledger()
        guard let account = contents.accounts.first(where: { $0.id == accountID }) else {
            return nil
        }
        let history = build(account: account, transactions: contents.transactions, today: today)
        return AccountHistoryPage(account: account, history: history, ledger: contents)
    }
}

@MainActor
public struct DefaultSaveTransactionsUseCase: SaveTransactionsUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func save(_ transactions: [Transaction]) throws -> TransactionChange {
        try repository.atomically { try saveAll(transactions) }
    }

    private func saveAll(_ transactions: [Transaction]) throws -> TransactionChange {
        let stored = Dictionary(uniqueKeysWithValues: try repository.transactions().map { ($0.id, $0) })
        var previous: [Transaction] = []
        for transaction in transactions {
            if let old = stored[transaction.id] {
                previous.append(old)
            }
            try repository.saveTransaction(transaction)
        }
        return previous.isEmpty ? .added(transactions.map(\.id)) : .replaced(previous)
    }

    public func resolvePayee(named name: String, createdAt: Date) throws -> Payee? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let existing = try repository.payees()
            .first(where: {
                $0.deletedAt == nil && $0.name.compare(trimmed, options: [.caseInsensitive]) == .orderedSame
            })
        {
            return existing
        }
        let payee = Payee(name: trimmed, createdAt: createdAt)
        try repository.savePayee(payee)
        return payee
    }
}

@MainActor
public struct DefaultTransactionChangesUseCase: TransactionChangesUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func remove(ids: [UUID]) throws -> TransactionChange {
        try repository.atomically { try removeAll(ids: ids) }
    }

    public func outcome(of change: TransactionChange) throws -> ChangeOutcome {
        try ChangeChecker(repository: repository).outcome(of: change)
    }

    public func check(_ change: TransactionChange, expecting outcome: ChangeOutcome) throws -> ChangeCheck {
        try ChangeChecker(repository: repository).check(change, expecting: outcome)
    }

    public func revert(_ change: TransactionChange, expecting outcome: ChangeOutcome) throws -> RevertResult {
        try repository.atomically {
            let checker = ChangeChecker(repository: repository)
            if case .stale(let reason) = try checker.check(change, expecting: outcome) {
                return .stale(reason)
            }
            let inverse = try revertAll(change, expecting: outcome)
            return .reverted(inverse, try checker.outcome(of: inverse))
        }
    }

    public func impact(of change: TransactionChange) throws -> ChangeImpact {
        // Every version the change touches: before it and, for an edit or an add, after it (D166.3).
        let current = try repository.transactions()
        let versions: [Transaction] =
            switch change {
            case .removed(let items): items.map(\.transaction)
            case .replaced(let previous):
                previous + current.filter { now in previous.contains { $0.id == now.id } }
            case .added(let ids): current.filter { ids.contains($0.id) }
            // Whole-account changes carry their account in the change itself.
            case .removedAccount, .addedAccount: []
            }
        let ids = Set(versions.flatMap { [$0.accountID, $0.transferAccountID].compactMap(\.self) })
        let transfers = versions.compactMap { version -> TransferImpact? in
            guard version.type == .transfer, let source = version.accountID,
                let destination = version.transferAccountID
            else {
                return nil
            }
            return TransferImpact(
                transactionID: version.id,
                sourceAccountID: source,
                destinationAccountID: destination,
            )
        }
        return ChangeImpact(
            accountIDs: ids,
            accounts: try repository.accounts().filter { ids.contains($0.id) },
            transactionIDs: change.transactionIDs,
            transfers: transfers,
        )
    }

    private func removeAll(ids: [UUID]) throws -> TransactionChange {
        .removed(try LedgerRemoval(repository: repository).transactions(ids: ids))
    }

    private func restore(_ items: [RemovedTransaction]) throws {
        for item in items {
            try repository.saveTransaction(item.transaction)
            for attachment in item.attachments {
                try repository.saveAttachment(attachment)
            }
            if !item.splits.isEmpty {
                try repository.replaceSplits(item.splits, for: item.transaction.id)
            }
        }
    }

    private func revertAll(_ change: TransactionChange, expecting outcome: ChangeOutcome) throws -> TransactionChange {
        switch change {
        case .removed(let items):
            try restore(items)
            return .added(items.map(\.transaction.id))
        case .removedAccount(let removed):
            try repository.saveAccount(removed.account)
            try restore(removed.transactions)
            return .addedAccount(removed.account.id)
        case .addedAccount(let id):
            return .removedAccount(try LedgerRemoval(repository: repository).account(id))
        case .added(let ids):
            return try removeAll(ids: ids)
        case .replaced(let previous):
            let current = Dictionary(uniqueKeysWithValues: try repository.transactions().map { ($0.id, $0) })
            var inverse: [Transaction] = []
            for old in previous {
                guard let now = current[old.id] else {
                    continue
                }
                inverse.append(now)
                guard now != outcome.transactions[old.id] else {
                    // Nothing else changed it: the earlier version goes back as it was.
                    try repository.saveTransaction(old)
                    continue
                }
                // Another window changed fields this change didn't touch; those keep their new values.
                var merged = now
                for field in outcome.touchedFields[old.id] ?? Set(TransactionField.allCases) {
                    field.copy(from: old, into: &merged)
                }
                try repository.saveTransaction(merged)
            }
            return .replaced(inverse)
        }
    }
}

/// Deletes transactions or a whole account, keeping copies so Undo can put everything back. Both the account
/// delete (`DeleteAccountUseCase`) and Redo of a restored account use it, so there is one way to delete an
/// account (#93). Callers run it inside `atomically`.
///
/// Known gap (sync, #21): `transactions()` returns only live rows, so an account's soft-deleted transactions
/// (tombstones), which `LedgerBook.deletingAccount` also removes, aren't kept and don't come back on Undo.
@MainActor
struct LedgerRemoval {
    let repository: any LedgerRepository

    /// Deletes these transactions with their attachments and splits. Ids that are gone are skipped.
    func transactions(ids: [UUID]) throws -> [RemovedTransaction] {
        let all = try repository.transactions()
        var removed: [RemovedTransaction] = []
        for id in ids {
            guard let transaction = all.first(where: { $0.id == id }) else {
                continue
            }
            removed.append(
                RemovedTransaction(
                    transaction: transaction,
                    attachments: try repository.attachments(for: id),
                    splits: try repository.splits(for: id),
                )
            )
            try repository.deleteTransaction(id: id)
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

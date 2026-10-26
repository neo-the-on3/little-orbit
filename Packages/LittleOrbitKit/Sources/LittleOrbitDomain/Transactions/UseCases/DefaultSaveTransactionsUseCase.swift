import Foundation

@MainActor
public struct DefaultSaveTransactionsUseCase: SaveTransactionsUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func save(_ transactions: [Transaction]) throws -> TransactionChange {
        try repository.atomically { try saveAll(transactions) }
    }

    public func save(_ transactions: [Transaction], creating payees: [Payee]) throws -> TransactionChange {
        try repository.atomically {
            let change = try saveAll(transactions)
            return .saved(change, creating: try PayeeCleanup(repository: repository).stored(payees))
        }
    }

    private func saveAll(_ transactions: [Transaction]) throws -> TransactionChange {
        let all = try repository.transactions()
        let stored = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var previous: [Transaction] = []
        for transaction in transactions {
            if let old = stored[transaction.id] {
                previous.append(old)
            } else if transaction.isRefund && transaction.refundOfID == nil {
                // A refund always starts from an expense; only import and sync bring in unlinked ones (D35.2).
                throw LedgerValidationError.refundNeedsOriginal
            }
            try repository.saveTransaction(transaction)
        }
        // Records the save changed as well, such as refunds following their expense's category (D33.4), go
        // into the same change, so one Undo reverts them all.
        let saved = Set(transactions.map(\.id))
        let current = Dictionary(uniqueKeysWithValues: try repository.transactions().map { ($0.id, $0) })
        for old in all where !saved.contains(old.id) {
            if let now = current[old.id], !TransactionField.changed(from: old, to: now).isEmpty {
                previous.append(old)
            }
        }
        return previous.isEmpty ? .added(transactions.map(\.id)) : .replaced(previous)
    }

    public func resolvePayee(named name: String, createdAt: Date) throws -> ResolvedPayee? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let existing = try repository.payees().first(where: { $0.isLive(named: trimmed) }) {
            return ResolvedPayee(payee: existing, isNew: false)
        }
        let payee = Payee(name: trimmed, createdAt: createdAt)
        try repository.savePayee(payee)
        let stored = try repository.payees().first { $0.id == payee.id } ?? payee
        return ResolvedPayee(payee: stored, isNew: true)
    }
}

import Foundation

/// Saving a transaction with split lines as one Undo step (#34, D64). Removing a split is a save with no lines
/// and `SplitRemoval.keptCategory` (D97.2).
@MainActor
public protocol SplitTransactionUseCase {
    /// Saves `transaction` with `lines`, all or none. Two or more lines make it a split, so its own category
    /// must be nil; no lines make it a normal transaction and drop any lines it had. Returns the change:
    /// `.added` for a new transaction; for an edit, `.replaced` with the stored version, wrapped in
    /// `.restoringLines` when the lines changed, so Undo restores both. Throws the `LedgerValidationError` a
    /// line breaks, such as `.splitRuleBroken(.linesDoNotMatchTotal)`, and writes nothing.
    func save(_ transaction: Transaction, lines: [TransactionSplit]) throws -> TransactionChange
}

@MainActor
public struct DefaultSplitTransactionUseCase: SplitTransactionUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func save(_ transaction: Transaction, lines: [TransactionSplit]) throws -> TransactionChange {
        try repository.atomically {
            guard let stored = try repository.transactions().first(where: { $0.id == transaction.id }) else {
                try repository.saveTransaction(transaction)
                if !lines.isEmpty {
                    try repository.replaceSplits(lines, for: transaction.id)
                }
                return .added([transaction.id])
            }
            let before = try repository.splits(for: transaction.id)
            // The lines come off first, so a split can go back to one category in the same save.
            try repository.replaceSplits([], for: transaction.id)
            try repository.saveTransaction(transaction)
            if !lines.isEmpty {
                // A line that stays keeps its creation date; only what changed is new.
                let created = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.createdAt) })
                let kept = lines.map { line in
                    var line = line
                    line.createdAt = created[line.id] ?? line.createdAt
                    return line
                }
                try repository.replaceSplits(kept, for: transaction.id)
            }
            let after = try repository.splits(for: transaction.id)
            let change = TransactionChange.replaced([stored])
            return SplitLineValue.of(before) == SplitLineValue.of(after)
                ? change : .restoringLines([transaction.id: before], change)
        }
    }
}

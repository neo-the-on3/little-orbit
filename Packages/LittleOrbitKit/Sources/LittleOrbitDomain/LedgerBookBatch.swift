import Foundation

/// What a batch of edits left (#285): the new snapshot, and the stored versions of every transaction it changed.
public struct LedgerBatchResult: Equatable, Sendable {
    /// The ledger after every row.
    public var snapshot: LedgerSnapshot
    /// The stored version of each row, in the rows' order, then of each other transaction the rows changed,
    /// such as a refund following its expense's category (D33.4), in stored order: the `.replaced` change that
    /// Undo applies, as `SaveTransactionsUseCase.save(_:)` records it.
    public var previous: [Transaction]
    /// The ids of `previous`, in the same order.
    public var changedIDs: [UUID] { previous.map(\.id) }

    public init(snapshot: LedgerSnapshot, previous: [Transaction]) {
        self.snapshot = snapshot
        self.previous = previous
    }
}

extension LedgerBook {
    /// How many rows a batch checks between progress reports.
    public static let batchProgressStride = 64

    /// Edits stored transactions as one batch (#285): the same result, and the same first error, as calling
    /// `updatingTransaction(_:in:now:)` for each row in turn, in order. Each row is checked against the ledger as
    /// the rows before it left it, so the order-dependent rules (a refund's currency and cap, an original's
    /// refunds, refund-category follow-through) give what the one-by-one saves give. The index is built once and
    /// the snapshot copied once, so a batch costs O(T + S + rows) rather than O(rows × T).
    ///
    /// `progress` gets how many rows are done every `batchProgressStride` rows and at the end; it may be called off
    /// the main actor. Between reports the batch stops with `CancellationError` if its task was cancelled. A throw
    /// leaves nothing changed: the caller keeps its snapshot.
    public static func updatingTransactions(
        _ rows: [Transaction],
        in snapshot: LedgerSnapshot,
        now: Date,
        progress: (@Sendable (Int) -> Void)? = nil,
    ) throws -> LedgerBatchResult {
        var index = LedgerIndex(snapshot)
        var previous: [Transaction] = []
        previous.reserveCapacity(rows.count)
        for (done, row) in rows.enumerated() {
            if done > 0, done.isMultiple(of: batchProgressStride) {
                progress?(done)
                try Task.checkCancellation()
            }
            // As stored before the batch, which `save(_:)` records for each row it saves.
            if let stored = index.position(of: row.id).map({ snapshot.transactions[$0] }), stored.deletedAt == nil {
                previous.append(stored)
            }
            try updatingTransaction(row, in: &index, now: now)
        }
        progress?(rows.count)
        // The other transactions the rows changed, as stored before, in stored order. Rows only replace in place,
        // so each position holds the same transaction before and after.
        let saved = Set(rows.map(\.id))
        let after = index.snapshot.transactions
        for position in snapshot.transactions.indices {
            let old = snapshot.transactions[position]
            guard old.deletedAt == nil, !saved.contains(old.id), after[position].deletedAt == nil,
                !TransactionField.changed(from: old, to: after[position]).isEmpty
            else {
                continue
            }
            previous.append(old)
        }
        return LedgerBatchResult(snapshot: index.snapshot, previous: previous)
    }
}

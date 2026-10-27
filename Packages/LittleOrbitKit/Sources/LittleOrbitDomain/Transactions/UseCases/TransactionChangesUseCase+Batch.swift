import Foundation
import LittleOrbitCore

/// An Undo or Redo of an edit built off the main actor (#285): the ledger to write, the change's inverse for the
/// next Undo or Redo, and the store revision it was built from.
public struct PreparedRevert: Equatable, Sendable {
    public var snapshot: LedgerSnapshot
    public var inverse: TransactionChange
    public var revision: UInt64

    public init(snapshot: LedgerSnapshot, inverse: TransactionChange, revision: UInt64) {
        self.snapshot = snapshot
        self.inverse = inverse
        self.revision = revision
    }
}

extension TransactionChangesUseCase {
    /// `revert(_:expecting:)` on the main actor, for a use case without a batch path.
    public func revert(
        _ change: TransactionChange,
        expecting outcome: ChangeOutcome,
        reporting _: LedgerBatchReporter,
    ) async throws -> RevertResult {
        try revert(change, expecting: outcome)
    }
}

extension DefaultTransactionChangesUseCase {
    /// Whether reverting `change` goes through the batch path: an edit (`.replaced`), with any payees its save
    /// created or its Undo removed. A Bulk Edit step is one.
    public nonisolated static func revertsInBatch(_ change: TransactionChange) -> Bool {
        if case .replaced = change.core {
            return true
        }
        return false
    }

    /// `revert(_:expecting:)` with the rows checked off the main actor (#285, D398): the stale check and the
    /// ledger read on the main actor, the reverted rows built on a detached task with the shared rules, then one
    /// write and one save on the main actor. If anything wrote in between, the commit checks the step again and
    /// builds it again from the ledger as it is then. Cancelled before the write, it writes nothing and throws
    /// `CancellationError`. Any other change, or a store without the batch path, reverts as `revert` does.
    public func revert(
        _ change: TransactionChange,
        expecting outcome: ChangeOutcome,
        reporting reporter: LedgerBatchReporter,
    ) async throws -> RevertResult {
        guard Self.revertsInBatch(change), repository.revision != nil else {
            return try revert(change, expecting: outcome)
        }
        if case .stale(let reason) = try ChangeChecker(repository: repository).check(change, expecting: outcome) {
            // Nothing is written (D187.5).
            return .stale(reason)
        }
        let base = try repository.batchBase()
        let rowsDone = reporter.rowsDone
        let prepared = try await LedgerBatchBase.build {
            try Self.preparedRevert(of: change, expecting: outcome, from: base, progress: rowsDone)
        }
        try Task.checkCancellation()
        let offMain = repository.savesBatchesOffMain
        await reporter.reportSaving(prepared.inverse.transactionIDs.count, offMain: offMain)
        try Task.checkCancellation()
        guard offMain else {
            return try commitRevert(prepared, of: change, expecting: outcome)
        }
        return try await commitRevertOffMain(prepared, of: change, expecting: outcome)
    }

    /// `commitRevert` for a store that saves off the main actor (#285, B): the stale check, and the rebuild if the
    /// store moved, run on the main actor right before the hand-off, with no suspension in between. What the
    /// revert leaves is read from the ledger it writes, as `commitRevert` reads it inside its change. If the
    /// store still moved by the hand-off, nothing is written and it's checked and built again.
    func commitRevertOffMain(
        _ prepared: PreparedRevert,
        of change: TransactionChange,
        expecting outcome: ChangeOutcome,
    ) async throws -> RevertResult {
        let span = BatchTrace.begin("batch.commit")
        defer { span.end() }
        var candidate: PreparedRevert? = prepared
        for _ in 0..<LedgerBatchBase.handOffAttempts {
            let revert: PreparedRevert
            switch try current(candidate, of: change, expecting: outcome) {
            case .stale(let reason):
                return .stale(reason)
            case .ready(let ready):
                revert = ready
            }
            let left = ChangeChecker.outcome(of: revert.inverse, among: revert.snapshot.transactionsVisible())
            if try await repository.writeBatchOffMain(revert.snapshot, expectedRevision: revert.revision) {
                return .reverted(revert.inverse, left)
            }
            candidate = revert
        }
        throw LedgerBatchStale()
    }

    private enum CurrentRevert {
        case stale(StaleReason)
        case ready(PreparedRevert)
    }

    /// `prepared` if the store hasn't moved since it was built, otherwise the step checked and built again now.
    private func current(
        _ prepared: PreparedRevert?,
        of change: TransactionChange,
        expecting outcome: ChangeOutcome,
    ) throws -> CurrentRevert {
        if let prepared, prepared.revision == repository.revision {
            return .ready(prepared)
        }
        if case .stale(let reason) = try ChangeChecker(repository: repository).check(change, expecting: outcome) {
            return .stale(reason)
        }
        return .ready(
            try Self.preparedRevert(of: change, expecting: outcome, from: repository.batchBase(), progress: nil)
        )
    }

    /// Writes `prepared`, or, if the store's revision has moved since, checks the step and builds it again now,
    /// inside the same change, so nothing lands between the check and the write. One write or none.
    func commitRevert(
        _ prepared: PreparedRevert?,
        of change: TransactionChange,
        expecting outcome: ChangeOutcome,
    ) throws -> RevertResult {
        let span = BatchTrace.begin("batch.commit")
        defer { span.end() }
        return try repository.atomically {
            let checker = ChangeChecker(repository: repository)
            let revert: PreparedRevert
            switch try current(prepared, of: change, expecting: outcome) {
            case .stale(let reason):
                return .stale(reason)
            case .ready(let ready):
                revert = ready
            }
            try repository.writeBatch(revert.snapshot)
            return .reverted(revert.inverse, try checker.outcome(of: revert.inverse))
        }
    }

    /// The revert of a batch change as one pure step over `base`: `revertAll` for `.replaced` and its payee
    /// wrappers, in the same order, with `PayeeCleanup`'s rules on the ledger value.
    nonisolated static func preparedRevert(
        of change: TransactionChange,
        expecting outcome: ChangeOutcome,
        from base: LedgerBatchBase,
        progress: (@Sendable (Int) -> Void)?,
    ) throws -> PreparedRevert {
        var snapshot = base.snapshot
        let inverse = try reverting(change, expecting: outcome, in: &snapshot, now: base.now, progress: progress)
        return PreparedRevert(snapshot: snapshot, inverse: inverse, revision: base.revision)
    }

    private nonisolated static func reverting(
        _ change: TransactionChange,
        expecting outcome: ChangeOutcome,
        in snapshot: inout LedgerSnapshot,
        now: Date,
        progress: (@Sendable (Int) -> Void)?,
    ) throws -> TransactionChange {
        switch change {
        case .createdPayees(let payees, let change):
            // Undo: the change first, so the count no longer sees it; then its unused payees (D191.4).
            let inverse = try reverting(change, expecting: outcome, in: &snapshot, now: now, progress: progress)
            return .saved(inverse, removing: try PayeeCleanup.removingUnused(payees, from: &snapshot, now: now))
        case .removedPayees(let payees, let change):
            // Redo: the payees first, with their IDs, so the transactions can use them (D191.4a.3).
            let (restored, change) = try PayeeCleanup.restoring(payees, for: change, in: &snapshot, now: now)
            let inverse = try reverting(change, expecting: outcome, in: &snapshot, now: now, progress: progress)
            // As stored now: reapplying the transactions sets their default category again.
            return .saved(inverse, creating: PayeeCleanup.stored(restored, in: snapshot))
        case .replaced(let previous):
            return try revertingEdits(previous, expecting: outcome, in: &snapshot, now: now, progress: progress)
        case .removed, .added, .removedAccount, .addedAccount, .savedScheduledItem, .revertedScheduledItemSave:
            throw LedgerBatchUnsupported()
        }
    }

    /// Puts the earlier versions back, in one batch: each row as it was, or, where another window changed fields
    /// this change didn't touch, the current row with only the touched fields put back. Returns the inverse, the
    /// rows as they are now.
    nonisolated static func revertingEdits(
        _ previous: [Transaction],
        expecting outcome: ChangeOutcome,
        in snapshot: inout LedgerSnapshot,
        now: Date,
        progress: (@Sendable (Int) -> Void)?,
    ) throws -> TransactionChange {
        let current = Dictionary(
            snapshot.transactionsVisible().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        var inverse: [Transaction] = []
        var rows: [Transaction] = []
        for old in previous {
            guard let now = current[old.id] else {
                continue
            }
            inverse.append(now)
            rows.append(merged(old, into: now, expecting: outcome))
        }
        snapshot = try LedgerBook.updatingTransactions(rows, in: snapshot, now: now, progress: progress).snapshot
        return .replaced(inverse)
    }

    /// `old` as it goes back: as it was when nothing else changed the row, otherwise the current row with only the
    /// fields this change touched taken from `old`, so another window's changes to the rest stay.
    private nonisolated static func merged(
        _ old: Transaction,
        into now: Transaction,
        expecting outcome: ChangeOutcome,
    ) -> Transaction {
        guard now != outcome.transactions[old.id] else {
            return old
        }
        var merged = now
        for field in outcome.touchedFields[old.id] ?? Set(TransactionField.allCases) {
            field.copy(from: old, into: &merged)
        }
        return merged
    }

    /// `revertAll` for `.replaced`: one batch on a store with the batch path, row by row on any other.
    func revertEdits(_ previous: [Transaction], expecting outcome: ChangeOutcome) throws -> TransactionChange {
        guard repository.revision != nil else {
            return try revertEditsRowByRow(previous, expecting: outcome)
        }
        let base = try repository.batchBase()
        var snapshot = base.snapshot
        let inverse = try Self.revertingEdits(
            previous,
            expecting: outcome,
            in: &snapshot,
            now: base.now,
            progress: nil,
        )
        try repository.writeBatch(snapshot)
        return inverse
    }

    private func revertEditsRowByRow(
        _ previous: [Transaction],
        expecting outcome: ChangeOutcome,
    ) throws -> TransactionChange {
        let current = Dictionary(uniqueKeysWithValues: try repository.transactions().map { ($0.id, $0) })
        var inverse: [Transaction] = []
        for old in previous {
            guard let now = current[old.id] else {
                continue
            }
            inverse.append(now)
            try repository.saveTransaction(Self.merged(old, into: now, expecting: outcome))
        }
        return .replaced(inverse)
    }
}

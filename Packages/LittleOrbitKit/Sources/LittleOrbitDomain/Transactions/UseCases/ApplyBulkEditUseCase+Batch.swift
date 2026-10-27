import Foundation
import LittleOrbitCore

/// A Bulk Edit Apply built from one ledger value (#285): the rows to write, checked with the shared rules, and
/// any payee the typed name creates. It's built off the main actor; the commit writes it on the main actor.
public struct BulkEditChangeSet: Equatable, Sendable {
    /// The ledger to write, with any new payee, and the stored versions of the rows it changes.
    public var result: LedgerBatchResult
    /// The payee the typed name creates, as stored after the rows; empty when the name matched one.
    public var created: [Payee]
    /// Whether no selected row changes. Then nothing is written unless a payee is created.
    public var changesNoRow: Bool
    /// The store revision it was built from.
    public var revision: UInt64

    public init(result: LedgerBatchResult, created: [Payee], changesNoRow: Bool, revision: UInt64) {
        self.result = result
        self.created = created
        self.changesNoRow = changesNoRow
        self.revision = revision
    }
}

extension DefaultApplyBulkEditUseCase {
    /// `apply(_:)` with the rows checked off the main actor (#285, D398): the ledger is read on the main actor,
    /// the change set is built on a detached task, then one write and one save on the main actor. If anything
    /// wrote in between, the commit builds it again first, from the ledger as it is then, as a fresh Apply would.
    /// Cancelled before the write, it writes nothing and throws `CancellationError`.
    public func apply(
        _ request: BulkEditRequest,
        reporting reporter: LedgerBatchReporter,
    ) async throws -> TransactionChange {
        guard repository.revision != nil else {
            return try apply(request)
        }
        let base = try repository.batchBase()
        let rowsDone = reporter.rowsDone
        let changeSet = try await LedgerBatchBase.build {
            try Self.changeSet(for: request, from: base, progress: rowsDone)
        }
        try Task.checkCancellation()
        let offMain = repository.savesBatchesOffMain
        await reporter.reportSaving(changeSet.changesNoRow ? 0 : changeSet.result.previous.count, offMain: offMain)
        try Task.checkCancellation()
        guard offMain else {
            return try commit(changeSet, for: request)
        }
        return try await commitOffMain(changeSet, for: request, reporting: reporter)
    }

    /// `commit(_:for:)` for a store that saves off the main actor (#285, B): the revision check, and the rebuild
    /// if the store moved, run on the main actor right before the hand-off, with no suspension in between. If
    /// the store still moved by then, nothing is written and it's built again. One write or none. `handingOff` is
    /// reported before each hand-off (B1).
    func commitOffMain(
        _ prepared: BulkEditChangeSet,
        for request: BulkEditRequest,
        reporting reporter: LedgerBatchReporter,
    ) async throws -> TransactionChange {
        let span = BatchTrace.begin("batch.commit")
        defer { span.end() }
        var candidate: BulkEditChangeSet? = prepared
        for _ in 0..<LedgerBatchBase.handOffAttempts {
            let changeSet = try current(candidate, for: request)
            if changeSet.changesNoRow {
                return .replaced([])
            }
            reporter.handingOff()
            let written = try await repository.writeBatchOffMain(
                changeSet.result.snapshot,
                expectedRevision: changeSet.revision,
                beforeInstall: reporter.willInstall,
            )
            if written {
                return .saved(.replaced(changeSet.result.previous), creating: changeSet.created)
            }
            // Built from a store that has moved since: it's built again from the store as it is now (D399).
            candidate = changeSet
        }
        throw LedgerBatchStale()
    }

    /// Writes `prepared`, or, if the store's revision has moved since it was built, the change set built again
    /// now, inside the same change, so nothing lands between the check and the write. One write or none: any
    /// throw writes nothing (D398.3). If that rebuild breaks a rule, it throws `BulkEditDataChanged` (D399).
    func commit(_ prepared: BulkEditChangeSet?, for request: BulkEditRequest) throws -> TransactionChange {
        let span = BatchTrace.begin("batch.commit")
        defer { span.end() }
        return try repository.atomically {
            let changeSet = try current(prepared, for: request)
            // No row changed: write nothing, not even a payee the edit typed, so an Apply with no Undo step leaves
            // nothing behind (N5).
            if changeSet.changesNoRow {
                return .replaced([])
            }
            try repository.writeBatch(changeSet.result.snapshot)
            // A payee this edit created goes with it on Undo, unless something else uses it by then (D191.4).
            return .saved(.replaced(changeSet.result.previous), creating: changeSet.created)
        }
    }

    /// `prepared` if the store hasn't moved since it was built, otherwise the change set built again now, from
    /// the store as it is. If that rebuild breaks a rule, it throws `BulkEditDataChanged` (D399).
    private func current(_ prepared: BulkEditChangeSet?, for request: BulkEditRequest) throws -> BulkEditChangeSet {
        if let prepared, prepared.revision == repository.revision {
            return prepared
        }
        let base = try repository.batchBase()
        do {
            return try Self.changeSet(for: request, from: base, progress: nil)
        } catch is LedgerValidationError where prepared != nil {
            // It passed the rules as built; the data changed since and it no longer does (D399).
            throw BulkEditDataChanged()
        }
    }

    /// The Apply as one pure step over `base` (D393, D395): the selection must still be stored, the ticked
    /// fields go onto the rows as stored now, a typed payee is found or created, and the changed rows are checked
    /// in order with the shared rules (`LedgerBook.updatingTransactions`).
    nonisolated static func changeSet(
        for request: BulkEditRequest,
        from base: LedgerBatchBase,
        progress: (@Sendable (Int) -> Void)?,
    ) throws -> BulkEditChangeSet {
        var snapshot = base.snapshot
        // Every selected row, changed by this edit or not: the sheet's count and its rows must still be stored.
        let stored = Dictionary(
            snapshot.transactionsVisible().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        let deleted = Set(request.selection.map(\.id).filter { stored[$0] == nil })
        guard deleted.isEmpty else {
            throw BulkEditSelectionDeleted(ids: deleted)
        }
        // The ticked fields go onto the rows as stored now, not as the sheet read them (D395).
        let current = request.selection.compactMap { stored[$0.id] }
        var changes = request.changes
        var created: [Payee] = []
        // Payee skips transfers (D114), so a transfers-only selection never creates a typed payee.
        if changes.payeeID != nil, current.contains(where: { $0.type != .transfer }) {
            let resolved = try DefaultSaveTransactionsUseCase.resolvePayee(
                named: request.payeeName,
                createdAt: request.now,
                in: &snapshot,
                now: base.now,
            )
            changes.payeeID = .some(resolved?.payee.id)
            created = resolved.flatMap { $0.isNew ? [$0.payee] : nil } ?? []
        }
        let updated = BulkEditRules.apply(
            changes,
            to: current,
            accounts: request.accounts,
            timeZoneID: request.timeZoneID,
        )
        let changed = zip(current, updated).filter { $0 != $1 }.map(\.1)
        guard !changed.isEmpty else {
            return BulkEditChangeSet(
                result: LedgerBatchResult(snapshot: snapshot, previous: []),
                created: created,
                changesNoRow: true,
                revision: base.revision,
            )
        }
        let result = try LedgerBook.updatingTransactions(changed, in: snapshot, now: base.now, progress: progress)
        return BulkEditChangeSet(
            result: result,
            // As stored after the rows, which set its default category (D191.4a.1).
            created: PayeeCleanup.stored(created, in: result.snapshot),
            changesNoRow: false,
            revision: base.revision,
        )
    }
}

extension DefaultSaveTransactionsUseCase {
    /// `resolvePayee(named:createdAt:)` on a ledger value: the live payee with this name, ignoring case, or a new
    /// one saved into `snapshot` with `LedgerBook.savingPayee`. `nil` for a blank name.
    nonisolated static func resolvePayee(
        named name: String,
        createdAt: Date,
        in snapshot: inout LedgerSnapshot,
        now: Date,
    ) throws -> ResolvedPayee? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let existing = snapshot.payeesVisible().first(where: { $0.isLive(named: trimmed) }) {
            return ResolvedPayee(payee: existing, isNew: false)
        }
        let payee = Payee(name: trimmed, createdAt: createdAt)
        snapshot = try LedgerBook.savingPayee(payee, in: snapshot, now: now)
        let stored = snapshot.payeesVisible().first { $0.id == payee.id } ?? payee
        return ResolvedPayee(payee: stored, isNew: true)
    }
}

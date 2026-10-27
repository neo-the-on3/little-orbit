#if canImport(SwiftData)
    import Foundation
    import LittleOrbitCore
    import LittleOrbitDomain
    import SwiftData

    /// A Bulk Edit, its Undo and its Redo saved on a background model actor (#285, B). On the main actor: the
    /// caller's revision check, the diff and the checks against the ledger in memory (`bg.presave`), then the
    /// hand-off of a plan of identifiers and values (`BackgroundBatchPlan`). The writer saves once in its own
    /// context. Back on the main actor, in one step (`bg.install`), the long-lived context, whose records no longer
    /// match the store, is swapped for a fresh one; the ledger in memory is rebuilt from the values already built
    /// and read back, with its records found by identifier in the fresh context, without fetching the store; and
    /// the revision moves on. A failed save, or a write that landed during it, drops the ledger in memory and the
    /// context instead, as after any failed write, so the next read loads the store again.
    extension SwiftDataLedgerRepository: BackgroundBatchStore {
        public var savesBatchesOffMain: Bool { true }

        public func writeBatchOffMain(_ snapshot: LedgerSnapshot, expectedRevision: UInt64) async throws -> Bool {
            try await writeBatchOffMain(snapshot, expectedRevision: expectedRevision, beforeInstall: {})
        }

        public func writeBatchOffMain(
            _ snapshot: LedgerSnapshot,
            expectedRevision: UInt64,
            beforeInstall: @escaping @MainActor @Sendable () async -> Void,
        ) async throws -> Bool {
            guard writes == expectedRevision else {
                return false
            }
            guard batch == nil else {
                // Inside `atomically`, it joins the change's one save.
                try writeBatch(snapshot)
                return true
            }
            try await BackgroundBatchSave.run(snapshot, in: self, beforeInstall: beforeInstall)
            return true
        }

        var writeCount: UInt64 { writes }

        var beforeInstall: (() -> Void)? { beforeBackgroundInstall }

        func prepareBackgroundBatch(
            _ snapshot: LedgerSnapshot
        ) throws -> BackgroundBatchPreparation<BackgroundBatchPlan<PersistentIdentifier>> {
            let current = try storedLedger()
            // The test hooks and overrides of the main-actor write keep it, as do the stores it rewrites whole.
            guard !current.needsWholeStoreWrite, beforeSave == nil, afterStep == nil, afterSave == nil,
                deletePathOverride == nil, linksFromParentsOverride == nil
            else {
                return .onMain
            }
            let changes = BatchTrace.interval("write.diff") { LedgerWriteSet(from: current.snapshot, to: snapshot) }
            guard changes.wholeStoreReason == nil else {
                return .onMain
            }
            guard !changes.isEmpty else {
                return .nothing
            }
            guard LedgerWriteTuning.deletePath(forDeleting: changes.deletedCount) != .wholeStore else {
                return .onMain
            }
            try BatchTrace.interval("write.validate") {
                try LedgerWriteValidation.validate(
                    changes,
                    of: snapshot,
                    storedAttachmentIDs: Set(current.attachments.keys),
                )
            }
            let plan = BatchTrace.interval("bg.plan", count: changes.transactions.upserted.count) {
                BackgroundBatchPlan<PersistentIdentifier>
                    .make(changes, from: current.snapshot, to: snapshot) {
                        current.recordID($0, $1)
                    }
            }
            guard let plan else {
                return .onMain
            }
            return .background(plan)
        }

        func writeBatchOnMain(_ snapshot: LedgerSnapshot) throws {
            try write(snapshot)
        }

        func backgroundSave(
            _ plan: BackgroundBatchPlan<PersistentIdentifier>
        ) -> @Sendable () async throws -> BackgroundBatchReceipt<PersistentIdentifier> {
            let container = self.container
            // The test switch is read here, on the main actor, and crosses as a value, not in the plan.
            let failsBeforeSave = backgroundSaveFails
            return {
                let writer = await BackgroundLedgerWriter.make(for: container)
                return try await writer.save(plan, failingBeforeSave: failsBeforeSave)
            }
        }

        func install(
            _ receipt: BackgroundBatchReceipt<PersistentIdentifier>,
            of plan: BackgroundBatchPlan<PersistentIdentifier>,
            writing snapshot: LedgerSnapshot,
        ) {
            writes &+= 1
            let fresh = Self.writerContext(container)
            let installed = stored.flatMap { old in
                SwiftDataStoredLedger.installing(
                    BackgroundBatchPlan.installed(snapshot, readBack: receipt),
                    replacing: old,
                    createdPayees: receipt.createdPayees,
                    removedPayees: Set(plan.removedPayees.map(\.id)),
                    in: fresh,
                )
            }
            adoptContext(fresh)
            // Should a record not be found in the fresh context, the next read loads the store again.
            stored = installed
            createdRecords = []
        }

        func dropCache(after error: (any Error)?) {
            if let error {
                discardChanges(after: error)
                return
            }
            // Another write saved during the background save: the store has both, the ledger in memory neither.
            writes &+= 1
            adoptContext(Self.writerContext(container))
            stored = nil
            createdRecords = []
        }
    }
#endif

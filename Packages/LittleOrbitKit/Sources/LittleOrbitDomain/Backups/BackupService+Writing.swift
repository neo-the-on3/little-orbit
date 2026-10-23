import Foundation

/// Writing one backup folder, checking it as written, and pruning after a good automatic backup.
extension BackupService {
    /// Encodes and writes one backup folder off the main actor, then checks it as written (D196.3). Only after a
    /// restorable automatic backup is in place are old automatic backups pruned; a failed backup prunes nothing
    /// (D62, D195.6).
    ///
    /// `ledger` comes without attachment bytes. Each attachment is hashed from `bytes` in chunks, unless `entries`
    /// already has them, then written to the folder from `bytes` the same way, or cloned from the earlier backup
    /// when its manifest has the same size and SHA-256 for it (B1, D195.1). If the new folder then fails its check
    /// and anything was cloned, the earlier backup is checked in full, which marks it 'Damaged' when it is, and
    /// the folder is written again with nothing cloned (B3).
    ///
    /// With `requiringCheck`, anything but a restorable result throws `beforeRestoreFailed`, after the backup is
    /// listed as it is (D63, B3). Cancelling the task stops between chunks and leaves no folder.
    func makeBackup(
        _ kind: BackupKind,
        of ledger: LedgerSnapshot,
        bytes source: any BackupAttachmentReading,
        entries known: [UUID: BackupFileEntry]? = nil,
        requiringCheck: Bool = false,
    ) async throws -> BackupRecord {
        let catalog = try await loadCatalog()
        let createdAt = now()
        let nameIndex = BackupNaming.nameIndex(for: createdAt, existing: catalog.records)
        let visible = (
            accounts: ledger.accountsVisible().count,
            transactions: ledger.transactionsVisible().count,
            attachments: ledger.attachmentsVisible().count,
        )
        let month = BackupMonth.string(for: createdAt, in: timeZone())
        let id = UUID()
        let manifest = BackupManifest(
            kind: kind,
            createdAt: createdAt,
            nameIndex: nameIndex,
            schemaVersion: schemaVersion,
            accountCount: visible.accounts,
            transactionCount: visible.transactions,
            attachmentCount: visible.attachments,
            month: month,
            id: id,
        )
        let codec = self.codec
        let storage = self.storage
        let bytes = BackupCancellableBytes(source)
        let earlier = catalog.restorable.newestFirst.first?.id
        let written: (summary: BackupFolderSummary, condition: BackupCondition?)
        do {
            written = try await Self.detached(priority: .utility) {
                let entries = try known ?? codec.attachmentEntries(of: ledger, reading: bytes)
                let files = try codec.encode(BackupContents(manifest: manifest, ledger: ledger), attachments: entries)
                let writes = try Self.attachmentWrites(
                    ledger,
                    entries: entries,
                    bytes: bytes,
                    earlier: earlier,
                    storage: storage,
                    codec: codec,
                )
                try storage.write(files, attachments: writes, id: id, cloningFrom: earlier)
                var condition = try Self.readBack(id, storage: storage, codec: codec)
                if condition == .damaged, let earlier, !writes.unchanged.isEmpty {
                    // A cloned file isn't what the earlier manifest says (B3): don't let it spread.
                    _ = try? Self.remembering(earlier, storage: storage) {
                        try codec.verify(storage.files(id: earlier))
                    }
                    try storage.delete(id: id)
                    var fresh = writes
                    fresh.unchanged = []
                    try storage.write(files, attachments: fresh, id: id, cloningFrom: nil)
                    condition = try Self.readBack(id, storage: storage, codec: codec)
                }
                let summary = try codec.summary(ofManifest: files[BackupFormat.manifestPath] ?? Data())
                return (summary, condition)
            }
        } catch BackupError.notEnoughStorage {
            // The list's line is for Back Up Now and automatic backups only; a restore says so in its alert (D211.8).
            // A status that can't be read is never saved over (R3): the line is lost, the status kept.
            if kind != .beforeRestore, var status = try? storage.loadStatus() {
                status.lastFailure = .notEnoughStorage
                try? storage.saveStatus(status)
            }
            throw BackupError.notEnoughStorage
        }
        let record = BackupRecord(
            id: id,
            kind: kind,
            createdAt: createdAt,
            nameIndex: nameIndex,
            byteSize: written.summary.byteSize,
            accountCount: visible.accounts,
            transactionCount: visible.transactions,
            attachmentCount: visible.attachments,
            fingerprint: written.summary.fingerprint,
            month: month,
            condition: written.condition ?? .restorable,
        )
        if var status = try? storage.loadStatus() {
            status.lastFailure = nil
            status.known[id] = record
            try? storage.saveStatus(status)
        }
        if requiringCheck, written.condition != .restorable {
            throw BackupError.beforeRestoreFailed
        }
        if kind == .automatic, written.condition == .restorable,
            let pruned = try? await toPrune(catalog.records + [record], settings.retention())
        {
            for old in pruned {
                try? storage.delete(id: old.id)
            }
        }
        return record
    }

    /// The new folder checked file by file, right after it's written, never a second copy of it (B1.2): `nil` when
    /// the check itself couldn't run. Cancelled meanwhile, the folder is removed, so none is left unchecked.
    nonisolated static func readBack(
        _ id: UUID,
        storage: any BackupStorage,
        codec: BackupCodec,
    ) throws -> BackupCondition? {
        do {
            _ = try codec.verify(storage.files(id: id))
            return .restorable
        } catch BackupError.damaged {
            return .damaged
        } catch is CancellationError {
            try? storage.delete(id: id)
            throw CancellationError()
        } catch {
            return nil
        }
    }

    /// `work` off the main actor. Cancelling the calling task cancels it too, which a detached task doesn't do by
    /// itself; the work checks for that between chunks (`BackupCancellableBytes`).
    nonisolated static func detached<Value: Sendable>(
        priority: TaskPriority,
        _ work: @escaping @Sendable () throws -> Value,
    ) async throws -> Value {
        let task = Task.detached(executorPreference: BackupWorkExecutor.shared, priority: priority) { try work() }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

/// Attachment bytes that stop with `CancellationError` before any chunk once the task is cancelled, so a backup
/// stopped by the system ends promptly, between chunks (background expiry).
struct BackupCancellableBytes: BackupAttachmentReading {
    let base: any BackupAttachmentReading

    init(_ base: any BackupAttachmentReading) {
        self.base = base
    }

    func stream(_ id: UUID, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        try Task.checkCancellation()
        return try base.stream(id) { chunk in
            try Task.checkCancellation()
            try body(chunk)
        }
    }

    func mappedData(for id: UUID) throws -> Data? {
        try Task.checkCancellation()
        return try base.mappedData(for: id)
    }
}

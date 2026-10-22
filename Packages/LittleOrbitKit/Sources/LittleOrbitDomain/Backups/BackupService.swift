import Foundation

/// The backup rules over the ledger, the backup folders, the archive and the checksums.
@MainActor
public final class BackupService: AllBackupUseCases {
    public private(set) var isBusy = false
    /// The backups being written to an export file. Delete refuses them and cleanup keeps them until it runs again,
    /// so a folder never goes mid-export (Tech Architect, non-blocking 3). Each export counts, so one window's
    /// export finishing never unlocks a backup another window is still exporting.
    private let exports = BackupExportCounts()

    private let source: any LedgerBackupSource
    let storage: any BackupStorage
    let archiving: any BackupArchiving
    let settings: any BackupSettingsStore
    let codec: BackupCodec
    private let changes: LedgerChanges
    let schemaVersion: String
    let now: @MainActor () -> Date
    let timeZone: @MainActor () -> TimeZone

    public init(
        source: any LedgerBackupSource,
        storage: any BackupStorage,
        archiving: any BackupArchiving,
        settings: any BackupSettingsStore,
        hashing: any BackupHashing,
        changes: LedgerChanges,
        schemaVersion: String,
        now: @escaping @MainActor () -> Date = { Date() },
        timeZone: @escaping @MainActor () -> TimeZone = { .current },
    ) {
        self.source = source
        self.storage = storage
        self.archiving = archiving
        self.settings = settings
        self.codec = BackupCodec(hashing: hashing)
        self.changes = changes
        self.schemaVersion = schemaVersion
        self.now = now
        self.timeZone = timeZone
    }

    public func overview() async throws -> BackupOverview {
        let catalog = try await loadCatalog()
        return BackupOverview(
            backups: catalog.newestFirst,
            lastFailure: catalog.lastFailure,
            retention: settings.retention(),
        )
    }

    public func backUpNow() async throws -> BackupRecord {
        try await exclusively {
            try await makeBackup(.manual, of: source.backupSnapshot(), bytes: source.attachmentBytes())
        }
    }

    public func backUpAutomaticallyIfNeeded() async throws -> BackupRecord? {
        guard !isBusy else {
            return nil
        }
        return try await exclusively { () async throws -> BackupRecord? in
            let catalog = try await loadCatalog()
            let moment = now()
            let zone = timeZone()
            if BackupPolicy.hasAutomaticBackup(on: moment, timeZone: zone, in: catalog) {
                return nil
            }
            let ledger = try source.backupSnapshot()
            let bytes = try source.attachmentBytes()
            let codec = self.codec
            let cancellable = BackupCancellableBytes(bytes)
            // Each attachment hashed in chunks, one at a time; the backup below reuses the entries (B1). Cancelling
            // the task, as the background expiry does, stops it between chunks.
            let (entries, fingerprint) = try await Self.detached(priority: .utility) {
                let entries = try codec.attachmentEntries(of: ledger, reading: cancellable)
                return (entries, try codec.fingerprint(of: ledger, attachments: entries))
            }
            let needed = BackupPolicy.needsAutomaticBackup(
                now: moment,
                timeZone: zone,
                catalog: catalog,
                currentFingerprint: fingerprint,
                ledgerIsEmpty: BackupPolicy.isEmpty(ledger),
            )
            return needed ? try await makeBackup(.automatic, of: ledger, bytes: bytes, entries: entries) : nil
        }
    }

    public func deleteBackup(id: UUID) async throws {
        try await exclusively {
            let catalog = try await loadCatalog()
            guard catalog.records.contains(where: { $0.id == id }) else {
                throw BackupError.notFound
            }
            guard exports.count(of: id) == 0 else {
                throw BackupError.exporting
            }
            try storage.delete(id: id)
        }
    }

    /// The archive is written to its own file in the staging folder, a chunk at a time, every file hashed on the
    /// way and checked against the manifest, so nothing is held whole (B2). The caller hands it to the save panel or
    /// share sheet, then calls `discardExport`. A failed or cancelled export leaves no file.
    public func exportBackup(id: UUID, named name: String) async throws -> BackupExport {
        guard !isBusy else {
            throw BackupError.busy
        }
        let catalog = try await loadCatalog()
        guard let record = catalog.records.first(where: { $0.id == id }) else {
            throw BackupError.notFound
        }
        // Export… is unavailable for a damaged or newer-format backup (D196.3, D197.2).
        guard record.isRestorable else {
            throw record.condition == .newerFormat ? BackupError.newerFormat : BackupError.damaged
        }
        let storage = self.storage
        let codec = self.codec
        let archiving = self.archiving
        let file = BackupExport.fileName(name, id: id)
        exports.begin(id)
        defer { exports.end(id) }
        let url = try await Self.detached(priority: .userInitiated) {
            let url = try storage.makeExportFolder().appendingPathComponent(file)
            do {
                try Self.remembering(id, storage: storage) {
                    try codec.archive(storage.files(id: id), with: archiving, to: url)
                }
                return url
            } catch {
                storage.removeExport(url)
                throw error
            }
        }
        return BackupExport(file: url, record: record)
    }

    public func exportCount(of id: UUID) -> Int {
        exports.count(of: id)
    }

    /// `work`, with a backup that can't be read reported as `cleanupBlocked`: nothing is deleted (R3, D208.3).
    private static func blockingCleanup<Value>(_ work: () async throws -> Value) async throws -> Value {
        do {
            return try await work()
        } catch let error where BackupReadFailure.isReadFailure(error) {
            throw BackupError.cleanupBlocked
        }
    }

    public func discardExport(_ export: BackupExport) {
        storage.removeExport(export.file)
    }

    /// Checks a backup for the Restore warning, off the main actor, keeping nothing but its manifest (B1). A stored
    /// backup is hashed file by file, version first (D196.3, D197.1). A picked file goes through
    /// `BackupArchiveImport`: manifest entry, version, unsafe entries, then checksums in one streamed pass, so
    /// nothing is written anywhere and no attachment is held (D197a.1).
    public func checkBackup(_ source: BackupSource) async throws -> BackupManifest {
        let storage = self.storage
        let codec = self.codec
        let archiving = self.archiving
        return
            try await Task.detached(priority: .userInitiated) {
                switch source {
                case .stored(let id):
                    return try Self.remembering(id, storage: storage) {
                        try codec.verify(storage.files(id: id)).manifest
                    }
                case .archive(let archive):
                    return try BackupArchiveImport(archiving: archiving, codec: codec).check(archive).manifest
                }
            }
            .value
    }

    /// The Before restore backup first, and only if it's restorable is `source` checked again, file by file, and
    /// the data replaced; otherwise this throws `beforeRestoreFailed` with the data unchanged (D63, B3).
    /// Attachments go from file to store one at a time and are never all in memory: a stored backup's from its
    /// folder, a picked file's from a scratch folder they're unpacked into after every check passes (B1).
    public func restore(
        _ source: BackupSource,
        progress: @MainActor (BackupRestoreStep) -> Void,
    ) async throws -> BackupRecord {
        try await exclusively {
            progress(.savingCurrentData)
            // D63: the data is only replaced once its Before restore backup checked out as restorable (B3).
            let before = try await makeBackup(
                .beforeRestore,
                of: self.source.backupSnapshot(),
                bytes: self.source.attachmentBytes(),
                requiringCheck: true,
            )
            progress(.replacingData)
            let (opened, scratch) = try await openForRestore(source)
            defer { scratch?.remove() }
            try self.source.replaceLedger(with: opened.contents.ledger, attachments: opened.attachments)
            changes.ledgerReplaced()
            // The backup read is released by now, before the restored data is read back for the marker.
            try? await markRestored()
            progress(.finished)
            return before
        }
    }

    public func retention() -> BackupRetention {
        settings.retention()
    }

    public func cleanupPlan(for retention: BackupRetention) async throws -> BackupCleanupPlan {
        guard !isBusy else {
            throw BackupError.busy
        }
        return try await Self.blockingCleanup {
            let catalog = try await loadCatalog()
            return BackupCleanupPlan(retention: retention, backups: try await toPrune(catalog.records, retention))
        }
    }

    public func apply(_ plan: BackupCleanupPlan) async throws -> [BackupRecord] {
        try await exclusively {
            guard !plan.backups.isEmpty else {
                settings.setRetention(plan.retention)
                return []
            }
            // What goes is worked out before N and M are saved, so a backup that can't be read leaves the setting
            // as it was (D208.3).
            let counted = Set(plan.backups.map(\.id))
            let deleted = try await Self.blockingCleanup {
                let catalog = try await loadCatalog()
                return try await toPrune(catalog.records, plan.retention).filter { counted.contains($0.id) }
            }
            settings.setRetention(plan.retention)
            for record in deleted {
                try? storage.delete(id: record.id)
            }
            return deleted
        }
    }

    private func markRestored() async throws {
        let restored = try source.backupSnapshot()
        let bytes = try source.attachmentBytes()
        let codec = self.codec
        let fingerprint =
            try await Task.detached(priority: .userInitiated) {
                try codec.fingerprint(
                    of: restored,
                    attachments: codec.attachmentEntries(of: restored, reading: bytes),
                )
            }
            .value
        var status = try storage.loadStatus()
        status.restoredFingerprint = fingerprint
        try storage.saveStatus(status)
    }

    /// The backups, from the folders that exist (D195.3), read off the main actor. See `BackupService.catalog`.
    func loadCatalog() async throws -> BackupCatalog {
        let storage = self.storage
        let codec = self.codec
        return
            try await Task.detached(priority: .userInitiated) {
                try Self.catalog(storage: storage, codec: codec)
            }
            .value
    }

    /// What `retention` prunes from `records` now. Every backup that isn't of a newer format is checked in full
    /// first, so a damaged one is never counted, never a keeper and never pruned, and only undamaged ones count as
    /// restorable (D196.3, L30–L33). If a folder can't be read at all, this throws and nothing is pruned (R3).
    func toPrune(_ records: [BackupRecord], _ retention: BackupRetention) async throws -> [BackupRecord] {
        let storage = self.storage
        let codec = self.codec
        let moment = now()
        let zone = timeZone()
        let pruned =
            try await Task.detached(priority: .utility) {
                let checked = try Self.checkedInFull(records, storage: storage, codec: codec)
                return BackupPolicy.automaticBackupsToPrune(
                    in: checked,
                    retention: retention,
                    now: moment,
                    timeZone: zone,
                )
            }
            .value
        // One being exported stays until the next cleanup.
        return pruned.filter { exports.count(of: $0.id) == 0 }
    }

    func exclusively<T>(_ body: () async throws -> T) async throws -> T {
        guard !isBusy else {
            throw BackupError.busy
        }
        isBusy = true
        defer { isBusy = false }
        return try await body()
    }
}

extension BackupService {
    /// The list, built from the folders (D195.3). Each folder named by a backup ID is listed:
    /// - with a supported manifest whose files are all there at their listed sizes, and no failed check since:
    ///   restorable
    /// - with a newer format's manifest: `newerFormat`, never checksum-checked (D197.2)
    /// - with no manifest, an unreadable one, a missing file or one of the wrong size, or a failed check: damaged,
    ///   with the kind and date last known for it (D196.3, L29, L37)
    ///
    /// The cache in the status is rebuilt from the result. If a folder can't be read at all (the device is locked,
    /// an I/O error), that error is thrown, so a partial list is never shown (R3). A folder deleted meanwhile just
    /// drops out.
    nonisolated static func catalog(storage: any BackupStorage, codec: BackupCodec) throws -> BackupCatalog {
        var status = try storage.loadStatus()
        var records: [BackupRecord] = []
        for id in try storage.storedIDs() {
            let listing: BackupFolderListing
            do {
                listing = try storage.listing(id: id)
            } catch BackupError.notFound {
                continue
            }
            records.append(record(id, listing: listing, known: status.known[id], codec: codec))
        }
        let known = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if known != status.known {
            status.known = known
            try? storage.saveStatus(status)
        }
        return BackupCatalog(records: records, status: status)
    }

    nonisolated static func record(
        _ id: UUID,
        listing: BackupFolderListing,
        known: BackupRecord?,
        codec: BackupCodec,
    ) -> BackupRecord {
        guard let data = listing.manifest, let reading = try? codec.reading(manifest: data) else {
            var record =
                known
                ?? BackupRecord(
                    id: id,
                    kind: nil,
                    createdAt: listing.createdAt ?? BackupRecord.unknownDate,
                    formatVersion: 0,
                    byteSize: listing.totalSize,
                )
            record.condition = .damaged
            return record
        }
        switch reading {
        case .newer(let hints):
            return BackupRecord(
                id: id,
                kind: hints.kind ?? known?.kind,
                createdAt: hints.createdAt ?? known?.createdAt ?? listing.createdAt ?? BackupRecord.unknownDate,
                nameIndex: hints.nameIndex ?? known?.nameIndex ?? 1,
                formatVersion: hints.formatVersion,
                byteSize: listing.totalSize,
                month: hints.month,
                condition: .newerFormat,
            )
        case .supported(let summary):
            let manifest = summary.manifest
            let filesThere = summary.fileSizes.allSatisfy { path, size in listing.fileSizes[path] == size }
            let failedCheck = known?.condition == .damaged && known?.fingerprint == summary.fingerprint
            return BackupRecord(
                id: id,
                kind: manifest.kind,
                createdAt: manifest.createdAt,
                nameIndex: manifest.nameIndex,
                formatVersion: manifest.formatVersion,
                byteSize: summary.byteSize,
                accountCount: manifest.accountCount,
                transactionCount: manifest.transactionCount,
                attachmentCount: manifest.attachmentCount,
                fingerprint: summary.fingerprint,
                month: manifest.month,
                condition: filesThere && !failedCheck ? .restorable : .damaged,
            )
        }
    }
}

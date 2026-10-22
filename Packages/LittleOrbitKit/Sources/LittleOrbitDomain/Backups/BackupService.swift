import Foundation

/// The backup rules over the ledger, the backup folders, the archive and the checksums.
@MainActor
public final class BackupService: AllBackupUseCases {
    public private(set) var isBusy = false

    private let source: any LedgerBackupSource
    let storage: any BackupStorage
    let archiving: any BackupArchiving
    private let settings: any BackupSettingsStore
    let codec: BackupCodec
    private let changes: LedgerChanges
    private let schemaVersion: String
    private let now: @MainActor () -> Date
    private let timeZone: @MainActor () -> TimeZone

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
            // Each attachment hashed in chunks, one at a time; the backup below reuses the entries (B1).
            let (entries, fingerprint) =
                try await Task.detached(priority: .utility) {
                    let entries = try codec.attachmentEntries(of: ledger, reading: bytes)
                    return (entries, try codec.fingerprint(of: ledger, attachments: entries))
                }
                .value
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
            try storage.delete(id: id)
        }
    }

    public func exportBackup(id: UUID) async throws -> BackupExport {
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
        let data =
            try await Task.detached(priority: .userInitiated) {
                let files = try storage.read(id: id)
                _ = try Self.remembering(id, storage: storage) { try codec.verify(files) }
                return try archiving.archive(files)
            }
            .value
        return BackupExport(data: data, record: record)
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

    /// The whole backup, checked, off the main actor: a stored folder's listed files only, or a picked file after
    /// `checkBackup`'s steps. Writes nothing.
    public func openBackup(_ source: BackupSource) async throws -> BackupContents {
        let storage = self.storage
        let codec = self.codec
        let archiving = self.archiving
        return
            try await Task.detached(priority: .userInitiated) {
                switch source {
                case .stored(let id):
                    return try Self.remembering(id, storage: storage) {
                        try codec.decode(reading: storage.files(id: id))
                    }
                case .archive(let archive):
                    return try BackupArchiveImport(archiving: archiving, codec: codec).contents(of: archive)
                }
            }
            .value
    }

    /// The Before restore backup first. Only then is `source` checked again, file by file, and the data replaced.
    /// Attachments go from file to store one at a time and are never all in memory: a stored backup's from its
    /// folder, a picked file's from a scratch folder they're unpacked into after every check passes (B1).
    public func restore(
        _ source: BackupSource,
        progress: @MainActor (BackupRestoreStep) -> Void,
    ) async throws -> BackupRecord {
        try await exclusively {
            progress(.savingCurrentData)
            let before = try await makeBackup(
                .beforeRestore,
                of: self.source.backupSnapshot(),
                bytes: self.source.attachmentBytes(),
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

    /// Restores contents already read, for callers that have them.
    public func restore(
        _ contents: BackupContents,
        progress: @MainActor (BackupRestoreStep) -> Void,
    ) async throws -> BackupRecord {
        try await exclusively {
            progress(.savingCurrentData)
            let before = try await makeBackup(
                .beforeRestore,
                of: source.backupSnapshot(),
                bytes: source.attachmentBytes(),
            )
            progress(.replacingData)
            try replace(with: contents)
            try? await markRestored()
            progress(.finished)
            return before
        }
    }

    /// Replaces all data in one save. Only the skip-after-restore marker is left after this: if it can't be saved,
    /// the restore still succeeded, and the next automatic backup is just not skipped.
    private func replace(with contents: BackupContents) throws {
        try source.replaceLedger(with: contents.ledger)
        // The data is replaced now: every screen reloads. (#87: the app-wide undo history is cleared from the same
        // signal once it exists; see AppComposition.)
        changes.ledgerReplaced()
    }

    public func retention() -> BackupRetention {
        settings.retention()
    }

    public func cleanupPlan(for retention: BackupRetention) async throws -> BackupCleanupPlan {
        guard !isBusy else {
            throw BackupError.busy
        }
        let catalog = try await loadCatalog()
        return BackupCleanupPlan(retention: retention, backups: try await toPrune(catalog.records, retention))
    }

    public func apply(_ plan: BackupCleanupPlan) async throws -> [BackupRecord] {
        try await exclusively {
            settings.setRetention(plan.retention)
            guard !plan.backups.isEmpty else {
                return []
            }
            let catalog = try await loadCatalog()
            let counted = Set(plan.backups.map(\.id))
            let deleted = try await toPrune(catalog.records, plan.retention).filter { counted.contains($0.id) }
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
    private func loadCatalog() async throws -> BackupCatalog {
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
    private func toPrune(_ records: [BackupRecord], _ retention: BackupRetention) async throws -> [BackupRecord] {
        let storage = self.storage
        let codec = self.codec
        let moment = now()
        let zone = timeZone()
        return
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
    }

    private func exclusively<T>(_ body: () async throws -> T) async throws -> T {
        guard !isBusy else {
            throw BackupError.busy
        }
        isBusy = true
        defer { isBusy = false }
        return try await body()
    }

    /// Encodes and writes one backup folder off the main actor, then checks it as written (D196.3). Only after a
    /// restorable automatic backup is in place are old automatic backups pruned; a failed backup prunes nothing
    /// (D62, D195.6).
    ///
    /// `ledger` comes without attachment bytes. Each attachment is hashed from `bytes` in chunks, unless `entries`
    /// already has them, then written to the folder from `bytes` the same way, or cloned from the earlier backup
    /// when its manifest has the same size and SHA-256 for it (B1, D195.1).
    private func makeBackup(
        _ kind: BackupKind,
        of ledger: LedgerSnapshot,
        bytes: any BackupAttachmentReading,
        entries known: [UUID: BackupFileEntry]? = nil,
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
        let manifest = BackupManifest(
            kind: kind,
            createdAt: createdAt,
            nameIndex: nameIndex,
            schemaVersion: schemaVersion,
            accountCount: visible.accounts,
            transactionCount: visible.transactions,
            attachmentCount: visible.attachments,
            month: month,
        )
        let id = UUID()
        let codec = self.codec
        let storage = self.storage
        let earlier = catalog.restorable.newestFirst.first?.id
        let written: (summary: BackupFolderSummary, condition: BackupCondition?)
        do {
            written =
                try await Task.detached(priority: .utility) {
                    let entries = try known ?? codec.attachmentEntries(of: ledger, reading: bytes)
                    let files = try codec.encode(
                        BackupContents(manifest: manifest, ledger: ledger),
                        attachments: entries,
                    )
                    let writes = try Self.attachmentWrites(
                        ledger,
                        entries: entries,
                        bytes: bytes,
                        earlier: earlier,
                        storage: storage,
                        codec: codec,
                    )
                    try storage.write(files, attachments: writes, id: id, cloningFrom: earlier)
                    let summary = try codec.summary(ofManifest: files[BackupFormat.manifestPath] ?? Data())
                    // Checked right after it's written. `nil` when the check itself couldn't run.
                    let condition: BackupCondition?
                    do {
                        // File by file, never a second copy of what was just written (B1.2).
                        _ = try codec.verify(storage.files(id: id))
                        condition = .restorable
                    } catch BackupError.damaged {
                        condition = .damaged
                    } catch {
                        condition = nil
                    }
                    return (summary, condition)
                }
                .value
        } catch BackupError.notEnoughStorage {
            var status = (try? storage.loadStatus()) ?? BackupStatus()
            status.lastFailure = .notEnoughStorage
            try? storage.saveStatus(status)
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
        if kind == .automatic, written.condition == .restorable,
            let pruned = try? await toPrune(catalog.records + [record], settings.retention())
        {
            for old in pruned {
                try? storage.delete(id: old.id)
            }
        }
        return record
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

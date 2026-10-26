import Foundation

/// The backup rules over the ledger, the backup folders, the archive and the checksums.
@MainActor
public final class BackupService: AllBackupUseCases {
    public private(set) var isBusy = false
    /// The backups being written to an export file. Delete refuses them and cleanup keeps them until it runs again,
    /// so a folder never goes mid-export (Tech Architect, non-blocking 3). Each export counts, so one window's
    /// export finishing never unlocks a backup another window is still exporting.
    private let exports = BackupExportCounts()
    /// Each export handed out and not yet discarded, with its backup's ID.
    private var openExports: [URL: UUID] = [:]
    /// The backups whose folders were read for the list since this service was made (D208.2, D214).
    let listedThisSession = BackupListedThisSession()

    private let source: any LedgerBackupSource
    let storage: any BackupStorage
    let archiving: any BackupArchiving
    let settings: any BackupSettingsStore
    /// The shared settings written into each backup and put back by a restore (D96.1, D348).
    let sharedSettings: (any BackupSharedSettingsStore)?
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
        sharedSettings: (any BackupSharedSettingsStore)? = nil,
    ) {
        self.source = source
        self.storage = storage
        self.archiving = archiving
        self.settings = settings
        self.sharedSettings = sharedSettings
        self.codec = BackupCodec(hashing: hashing)
        self.changes = changes
        self.schemaVersion = schemaVersion
        self.now = now
        self.timeZone = timeZone
    }

    /// The list. A Backups folder or status file that can't be read is `loadFailed` (D211.5).
    public func overview() async throws -> BackupOverview {
        let catalog = try await Self.mapping(to: .loadFailed) { try await loadCatalog() }
        return BackupOverview(
            backups: catalog.newestFirst,
            lastFailure: catalog.lastFailure,
            retention: settings.retention(),
        )
    }

    /// Back Up Now. A full disk stays `notEnoughStorage`, the list's line (D62); any other failure is
    /// `backUpFailed` (D211.2).
    public func backUpNow() async throws -> BackupRecord {
        try await exclusively {
            try await Self.mapping(to: .backUpFailed) {
                try await makeBackup(.manual, of: source.backupSnapshot(), bytes: source.attachmentBytes())
            }
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
            let shared = currentSharedSettings()
            let codec = self.codec
            let cancellable = BackupCancellableBytes(bytes)
            // Each attachment hashed in chunks, one at a time; the backup below reuses the entries (B1). Cancelling
            // the task, as the background expiry does, stops it between chunks.
            let (entries, fingerprint) = try await Self.detached(priority: .utility) {
                let entries = try codec.attachmentEntries(of: ledger, reading: cancellable)
                // The shared settings count, as in the backup itself, so changing Show upcoming is a change.
                return (entries, try codec.fingerprint(of: ledger, attachments: entries, settings: shared))
            }
            let needed = BackupPolicy.needsAutomaticBackup(
                now: moment,
                timeZone: zone,
                catalog: catalog,
                currentFingerprint: fingerprint,
                ledgerIsEmpty: BackupPolicy.isEmpty(ledger),
            )
            return needed
                ? try await makeBackup(.automatic, of: ledger, bytes: bytes, entries: entries, shared: shared) : nil
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
            // A folder that can't be removed is `deleteFailed` (D211.3).
            try await Self.mapping(to: .deleteFailed) { try storage.delete(id: id) }
        }
    }

    /// The archive is written to its own file in the staging folder, a chunk at a time, every file hashed on the
    /// way and checked against the manifest, so nothing is held whole (B2). The caller hands it to the save panel or
    /// share sheet, then calls `discardExport`. A failed or cancelled export leaves no file.
    public func exportBackup(id: UUID, named name: String) async throws -> BackupExport {
        guard !isBusy else {
            throw BackupError.busy
        }
        // The save panel's copies from an earlier export, once no window has a panel up (Tester finding 3).
        if openExports.isEmpty {
            storage.removeSystemExportCopies()
        }
        // Held from the moment Export is chosen, before the list is read, until `discardExport`: after the save
        // panel's `onCompletion` or `onCancellation`, or a fallback, the next export or the window closing. Every
        // error on the way releases it. Nothing outlives a relaunch (D208.1, Tester finding 2).
        exports.begin(id)
        do {
            let catalog = try await loadCatalog()
            guard let record = catalog.records.first(where: { $0.id == id }) else {
                throw BackupError.notFound
            }
            // Export… is unavailable for a damaged, newer-format or unreadable backup (D196.3, D197.2, D214).
            switch record.condition {
            case .restorable: break
            case .damaged: throw BackupError.damaged
            case .newerFormat: throw BackupError.newerFormat
            case .unreadable: throw BackupError.unreadableBackup
            }
            let storage = self.storage
            let codec = self.codec
            let archiving = self.archiving
            let file = BackupExport.fileName(name, id: id)
            let url = try await Self.detached(priority: .userInitiated) {
                let url = try Self.staging { try storage.makeExportFolder().appendingPathComponent(file) }
                do {
                    try Self.remembering(id, storage: storage) {
                        let folder = try storage.files(id: id)
                        try Self.staging { try codec.archive(folder, with: archiving, to: url) }
                    }
                    return url
                } catch {
                    storage.removeExport(url)
                    throw error
                }
            }
            openExports[url] = id
            return BackupExport(file: url, record: record)
        } catch {
            exports.end(id)
            throw error
        }
    }

    /// `work`, with any error that isn't already a `BackupError` or a cancellation reported as `mapped`, so a
    /// system error's own text, which can name the store's files and folders, never leaves Domain (D211).
    static func mapping<Value>(to mapped: BackupError, _ work: () async throws -> Value) async throws -> Value {
        do {
            return try await work()
        } catch let thrown as CancellationError {
            throw thrown
        } catch let thrown as BackupError {
            throw thrown
        } catch {
            throw mapped
        }
    }

    /// `work`, staging an export's file before the save panel opens. Whatever it throws, a full disk included, is
    /// `exportFailed`, except what the backup itself reports: its files couldn't be read (`unreadableBackup`,
    /// D208.2), it's damaged or newer, or the task was cancelled (D211.4).
    private nonisolated static func staging<Value>(_ work: () throws -> Value) throws -> Value {
        do {
            return try work()
        } catch let error as CancellationError {
            throw error
        } catch let error as BackupFileReadError {
            throw error
        } catch let error as BackupError where error != .notEnoughStorage {
            throw error
        } catch {
            throw BackupError.exportFailed
        }
    }

    public func exportCount(of id: UUID) -> Int {
        exports.count(of: id)
    }

    /// `work`, with a backup that can't be read reported as `cleanupBlocked` (R3, D208.3) and any other failure,
    /// the list itself not reading included (`BackupListUnreadable`, D214.5), as `cleanupFailed` (D211.6). Either way nothing is deleted and N and M aren't saved, as both come after it.
    /// Cancelling passes through.
    private static func blockingCleanup<Value>(_ work: () async throws -> Value) async throws -> Value {
        do {
            return try await work()
        } catch let error as CancellationError {
            throw error
        } catch let error where BackupReadFailure.isReadFailure(error) {
            throw BackupError.cleanupBlocked
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.cleanupFailed
        }
    }

    /// Removes the export's file and releases its lock, once: a second call for the same export changes nothing.
    public func discardExport(_ export: BackupExport) {
        storage.removeExport(export.file)
        if let id = openExports.removeValue(forKey: export.file) {
            exports.end(id)
        }
        // The save panel's own copy, once no other window's panel may still be reading one (Tester finding 3).
        if openExports.isEmpty {
            storage.removeSystemExportCopies()
        }
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
            try await Task.detached(executorPreference: BackupWorkExecutor.shared, priority: .userInitiated) {
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

    /// The Before restore backup first, and only if it's made and restorable is `source` checked again, file by
    /// file, and the data replaced; otherwise this throws `beforeRestoreFailed` with the data unchanged (D63, B3).
    /// Attachments go from file to store one at a time and are never all in memory: a stored backup's from its
    /// folder, a picked file's from a scratch folder they're unpacked into after every check passes (B1).
    public func restore(
        _ source: BackupSource,
        progress: @MainActor (BackupRestoreStep) -> Void,
    ) async throws -> BackupRecord {
        try await exclusively {
            progress(.savingCurrentData)
            let before = try await makeBeforeRestoreBackup()
            progress(.replacingData)
            // From here the Before restore backup exists. A read error keeps its own alert (D207.2, D208.2); an
            // unpack or replace failure is `restoreFailed`, with nothing replaced (D211.1).
            let (opened, scratch) = try await Self.mapping(to: .restoreFailed) { try await openForRestore(source) }
            defer { scratch?.remove() }
            try await Self.mapping(to: .restoreFailed) {
                try self.source.replaceLedger(with: opened.contents.ledger, attachments: opened.attachments)
            }
            // The backup's shared settings come back with its data, before anything reloads (D96.1, D348).
            sharedSettings?.restoreSharedSettings(opened.contents.sharedSettings)
            changes.ledgerReplaced()
            // The backup read is released by now, before the restored data is read back for the marker.
            try? await markRestored()
            progress(.finished)
            return before
        }
    }

    /// The Before restore backup of the current data. D63: the data is only replaced once it checked out as
    /// restorable (B3). Any failure to make it, a write, a move, a staging folder or its check, is
    /// `beforeRestoreFailed`, so nothing of the store's own files or folders reaches the user (Tester F3, D207.1).
    /// A full disk is `notEnoughStorageToRestore`, and doesn't set the list's failure line, which is Back Up Now's
    /// only (D62, D211.8). Cancelling passes through.
    private func makeBeforeRestoreBackup() async throws -> BackupRecord {
        do {
            return try await makeBackup(
                .beforeRestore,
                of: source.backupSnapshot(),
                bytes: source.attachmentBytes(),
                requiringCheck: true,
            )
        } catch let error as CancellationError {
            throw error
        } catch BackupError.notEnoughStorage {
            throw BackupError.notEnoughStorageToRestore
        } catch {
            throw BackupError.beforeRestoreFailed
        }
    }

    public func retention() -> BackupRetention {
        settings.retention()
    }

    /// The shared settings as they are now, for the next backup; empty when the app keeps none.
    func currentSharedSettings() -> BackupSharedSettings {
        sharedSettings?.backupSharedSettings() ?? BackupSharedSettings()
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
        // With the shared settings the restore just put back, as the automatic backup's check counts them, so the
        // day after a restore makes no backup until something changes (S53, Tech Architect B1 on #203).
        let shared = currentSharedSettings()
        let codec = self.codec
        let fingerprint =
            try await Task.detached(executorPreference: BackupWorkExecutor.shared, priority: .userInitiated) {
                try codec.fingerprint(
                    of: restored,
                    attachments: codec.attachmentEntries(of: restored, reading: bytes),
                    settings: shared,
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
        let listed = listedThisSession
        return
            try await Task.detached(executorPreference: BackupWorkExecutor.shared, priority: .userInitiated) {
                try Self.catalog(storage: storage, codec: codec, listed: listed)
            }
            .value
    }

    /// What `retention` prunes from `records` now. Every backup that isn't of a newer format is checked in full
    /// first, so a damaged one is never counted, never a keeper and never pruned, and only undamaged ones count as
    /// restorable (D196.3, L30–L33). If a folder can't be read at all, this throws and nothing is pruned (R3).
    func toPrune(_ records: [BackupRecord], _ retention: BackupRetention) async throws -> [BackupRecord] {
        // A folder that couldn't be read at all stops cleanup, as one that fails its read below does (D208.3, D214).
        if records.contains(where: { $0.condition == .unreadable }) {
            throw BackupFileReadError(BackupError.unreadableBackup)
        }
        let storage = self.storage
        let codec = self.codec
        let moment = now()
        let zone = timeZone()
        let pruned =
            try await Task.detached(executorPreference: BackupWorkExecutor.shared, priority: .utility) {
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

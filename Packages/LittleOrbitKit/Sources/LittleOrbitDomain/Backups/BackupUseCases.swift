import Foundation

// The backup use cases (#40). View models depend only on these protocols. `BackupService` implements them over
// `LedgerBackupSource`, `BackupStorage` and `BackupCryptography`, which the App target wires in.

/// What Settings > Backups shows.
public struct BackupOverview: Equatable, Sendable {
    /// Newest first (S30).
    public var backups: [BackupRecord]
    public var lastFailure: BackupFailure?

    public init(backups: [BackupRecord] = [], lastFailure: BackupFailure? = nil) {
        self.backups = backups
        self.lastFailure = lastFailure
    }

    /// The newest backup of any kind, for the "Last backup" line.
    public var lastBackup: BackupRecord? {
        backups.first
    }
}

/// A backup file ready to save where the user chooses. The view model names it from `record`.
public struct BackupExport: Equatable, Sendable {
    public var data: Data
    public var record: BackupRecord
    public var isEncrypted: Bool

    public init(data: Data, record: BackupRecord, isEncrypted: Bool) {
        self.data = data
        self.record = record
        self.isEncrypted = isEncrypted
    }
}

/// A backup to restore: one in the list, or a file the user picked.
public enum BackupSource: Equatable, Sendable {
    case stored(UUID)
    case file(Data)
}

/// The steps a restore goes through, in order. There's no Cancel (D116.2).
public enum BackupRestoreStep: Int, Comparable, Equatable, Sendable {
    case savingCurrentData
    case replacingData
    case finished

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Tells every feature that the whole ledger was replaced, by a restore, so each reloads instead of showing (and
/// writing back) the old data. The composition root makes one and hands it to the backup service and every
/// feature that shows ledger data.
@MainActor
public final class LedgerChanges {
    /// How many times the ledger has been replaced since launch.
    public private(set) var replacements = 0
    private var observers: [@MainActor () -> Void] = []

    public init() {}

    /// Calls `handler` after each replacement.
    public func onReplacement(_ handler: @escaping @MainActor () -> Void) {
        observers.append(handler)
    }

    public func ledgerReplaced() {
        replacements += 1
        for observer in observers {
            observer()
        }
    }
}

@MainActor
public protocol ListBackupsUseCase {
    func overview() throws -> BackupOverview
}

@MainActor
public protocol MakeBackupUseCase {
    /// `true` while a backup or restore runs. Other backup actions are disabled, not queued (D118.5).
    var isBusy: Bool { get }
    /// 'Back Up Now'.
    func backUpNow() async throws -> BackupRecord
    /// The launch and background trigger. Returns `nil` when no backup is needed (D62, D116.3).
    func backUpAutomaticallyIfNeeded() async throws -> BackupRecord?
}

@MainActor
public protocol DeleteBackupUseCase {
    /// Removes any backup, Automatic included. Never starts a backup (D116.1, D118.1).
    func deleteBackup(id: UUID) throws
}

@MainActor
public protocol ExportBackupUseCase {
    /// The file for one backup, encrypted when `password` isn't empty (D63).
    func exportBackup(id: UUID, password: String?) async throws -> BackupExport
}

@MainActor
public protocol RestoreBackupUseCase {
    /// Reads and checks a backup without changing anything. Throws `damaged`, `newerFormat`, `passwordRequired`
    /// or `incorrectPassword`.
    func openBackup(_ source: BackupSource, password: String?) async throws -> BackupContents
    /// Makes a Before restore backup of the current data, then replaces all data with `contents` in one save.
    /// If either step fails, the data is unchanged. Returns the Before restore backup.
    func restore(
        _ contents: BackupContents,
        progress: @MainActor (BackupRestoreStep) -> Void,
    ) async throws -> BackupRecord
}

/// The backup use cases in one place, as the composition root wires them.
public struct BackupUseCases {
    public var list: any ListBackupsUseCase
    public var make: any MakeBackupUseCase
    public var delete: any DeleteBackupUseCase
    public var export: any ExportBackupUseCase
    public var restore: any RestoreBackupUseCase
    public var authentication: any AppAuthenticationUseCase

    public init(
        list: any ListBackupsUseCase,
        make: any MakeBackupUseCase,
        delete: any DeleteBackupUseCase,
        export: any ExportBackupUseCase,
        restore: any RestoreBackupUseCase,
        authentication: any AppAuthenticationUseCase,
    ) {
        self.list = list
        self.make = make
        self.delete = delete
        self.export = export
        self.restore = restore
        self.authentication = authentication
    }

    @MainActor
    /// `authentication` has no default, so the App Lock seam (#29) is always passed explicitly.
    public init(service: BackupService, authentication: any AppAuthenticationUseCase) {
        self.init(
            list: service,
            make: service,
            delete: service,
            export: service,
            restore: service,
            authentication: authentication,
        )
    }
}

/// Every backup use case, as one type the composition root can hand out.
public typealias AllBackupUseCases = ListBackupsUseCase & MakeBackupUseCase & DeleteBackupUseCase
    & ExportBackupUseCase & RestoreBackupUseCase

/// The backup rules over the ledger, the backup files and the cryptography.
@MainActor
public final class BackupService: AllBackupUseCases {
    public private(set) var isBusy = false

    private let source: any LedgerBackupSource
    private let storage: any BackupStorage
    private let codec: BackupCodec
    private let changes: LedgerChanges
    private let schemaVersion: String
    private let now: @MainActor () -> Date
    private let timeZone: @MainActor () -> TimeZone

    public init(
        source: any LedgerBackupSource,
        storage: any BackupStorage,
        cryptography: any BackupCryptography,
        changes: LedgerChanges,
        schemaVersion: String,
        allowedIterations: ClosedRange<Int> = BackupEncryption.allowedIterations,
        now: @escaping @MainActor () -> Date = { Date() },
        timeZone: @escaping @MainActor () -> TimeZone = { .current },
    ) {
        self.source = source
        self.storage = storage
        self.codec = BackupCodec(cryptography: cryptography, allowedIterations: allowedIterations)
        self.changes = changes
        self.schemaVersion = schemaVersion
        self.now = now
        self.timeZone = timeZone
    }

    public func overview() throws -> BackupOverview {
        let catalog = try loadCatalog()
        return BackupOverview(backups: catalog.newestFirst, lastFailure: catalog.lastFailure)
    }

    public func backUpNow() async throws -> BackupRecord {
        try await exclusively {
            let ledger = try source.ledgerSnapshot()
            return try await makeBackup(.manual, of: ledger)
        }
    }

    public func backUpAutomaticallyIfNeeded() async throws -> BackupRecord? {
        guard !isBusy else {
            return nil
        }
        return try await exclusively { () async throws -> BackupRecord? in
            let catalog = try loadCatalog()
            let moment = now()
            let zone = timeZone()
            if BackupPolicy.hasAutomaticBackup(on: moment, timeZone: zone, in: catalog) {
                return nil
            }
            let ledger = try source.ledgerSnapshot()
            let codec = self.codec
            let fingerprint =
                try await Task.detached(priority: .utility) {
                    try codec.fingerprint(of: ledger)
                }
                .value
            let needed = BackupPolicy.needsAutomaticBackup(
                now: moment,
                timeZone: zone,
                catalog: catalog,
                currentFingerprint: fingerprint,
                ledgerIsEmpty: BackupPolicy.isEmpty(ledger),
            )
            return needed ? try await makeBackup(.automatic, of: ledger) : nil
        }
    }

    public func deleteBackup(id: UUID) throws {
        guard !isBusy else {
            throw BackupError.busy
        }
        var catalog = try loadCatalog()
        guard catalog.records.contains(where: { $0.id == id }) else {
            throw BackupError.notFound
        }
        catalog.records.removeAll { $0.id == id }
        try storage.saveCatalog(catalog)
        try? storage.delete(id: id)
    }

    public func exportBackup(id: UUID, password: String?) async throws -> BackupExport {
        guard !isBusy else {
            throw BackupError.busy
        }
        let catalog = try loadCatalog()
        guard let record = catalog.records.first(where: { $0.id == id }) else {
            throw BackupError.notFound
        }
        let storage = self.storage
        let codec = self.codec
        let password = password ?? ""
        let data =
            try await Task.detached(priority: .userInitiated) {
                let stored = try storage.read(id: id)
                guard !password.isEmpty else {
                    _ = try codec.decode(stored)
                    return stored
                }
                return try codec.encode(codec.decode(stored), password: password)
            }
            .value
        return BackupExport(data: data, record: record, isEncrypted: !password.isEmpty)
    }

    public func openBackup(_ source: BackupSource, password: String?) async throws -> BackupContents {
        let storage = self.storage
        let codec = self.codec
        return
            try await Task.detached(priority: .userInitiated) {
                let data: Data
                switch source {
                case .stored(let id):
                    data = try storage.read(id: id)
                case .file(let file):
                    data = file
                }
                return try codec.decode(data, password: password)
            }
            .value
    }

    public func restore(
        _ contents: BackupContents,
        progress: @MainActor (BackupRestoreStep) -> Void,
    ) async throws -> BackupRecord {
        try await exclusively {
            progress(.savingCurrentData)
            let current = try source.ledgerSnapshot()
            let before = try await makeBackup(.beforeRestore, of: current)
            progress(.replacingData)
            try source.replaceLedger(with: contents.ledger)
            // The data is replaced now: every screen reloads. (#87: the app-wide undo history is cleared from
            // the same signal once it exists; see AppComposition.)
            changes.ledgerReplaced()
            // Only the skip-after-restore marker is left. If it can't be saved, the restore still succeeded; the
            // next automatic backup is just not skipped.
            try? await markRestored()
            progress(.finished)
            return before
        }
    }

    private func markRestored() async throws {
        let restored = try source.ledgerSnapshot()
        let codec = self.codec
        let fingerprint =
            try await Task.detached(priority: .userInitiated) {
                try codec.fingerprint(of: restored)
            }
            .value
        var catalog = try loadCatalog()
        catalog.restoredFingerprint = fingerprint
        try storage.saveCatalog(catalog)
    }

    /// The catalog, rebuilt from the stored files' manifests when `catalog.json` can't be read, so the list and
    /// automatic backups keep working (N3).
    private func loadCatalog() throws -> BackupCatalog {
        do {
            return try storage.loadCatalog()
        } catch BackupError.catalogUnreadable {
            var records: [BackupRecord] = []
            for id in try storage.storedIDs() {
                guard let data = try? storage.read(id: id), let contents = try? codec.decode(data) else {
                    continue
                }
                let manifest = contents.manifest
                records.append(
                    BackupRecord(
                        id: id,
                        kind: manifest.kind,
                        createdAt: manifest.createdAt,
                        nameIndex: manifest.nameIndex,
                        formatVersion: manifest.formatVersion,
                        byteSize: Int64(data.count),
                        accountCount: manifest.accountCount,
                        transactionCount: manifest.transactionCount,
                        attachmentCount: manifest.attachmentCount,
                        fingerprint: (try? codec.fingerprint(of: contents.ledger)) ?? "",
                    )
                )
            }
            let catalog = BackupCatalog(records: records)
            try storage.saveCatalog(catalog)
            return catalog
        }
    }

    private func exclusively<T>(_ body: () async throws -> T) async throws -> T {
        guard !isBusy else {
            throw BackupError.busy
        }
        isBusy = true
        defer { isBusy = false }
        return try await body()
    }

    /// Encodes and writes one backup off the main actor, then records it and prunes old automatic backups.
    private func makeBackup(_ kind: BackupKind, of ledger: LedgerSnapshot) async throws -> BackupRecord {
        var catalog = try loadCatalog()
        let createdAt = now()
        let nameIndex = BackupNaming.nameIndex(for: createdAt, existing: catalog.records)
        let visible = (
            accounts: ledger.accountsVisible().count,
            transactions: ledger.transactionsVisible().count,
            attachments: ledger.attachmentsVisible().count,
        )
        let manifest = BackupManifest(
            kind: kind,
            createdAt: createdAt,
            nameIndex: nameIndex,
            schemaVersion: schemaVersion,
            accountCount: visible.accounts,
            transactionCount: visible.transactions,
            attachmentCount: visible.attachments,
        )
        let id = UUID()
        let codec = self.codec
        let storage = self.storage
        let written: (size: Int64, fingerprint: String)
        do {
            written =
                try await Task.detached(priority: .utility) {
                    let contents = BackupContents(manifest: manifest, ledger: ledger)
                    let data = try codec.encode(contents)
                    let size = try storage.write(data, id: id)
                    return (size, try codec.fingerprint(of: ledger))
                }
                .value
        } catch BackupError.notEnoughStorage {
            catalog.lastFailure = .notEnoughStorage
            try? storage.saveCatalog(catalog)
            throw BackupError.notEnoughStorage
        }
        let record = BackupRecord(
            id: id,
            kind: kind,
            createdAt: createdAt,
            nameIndex: nameIndex,
            byteSize: written.size,
            accountCount: visible.accounts,
            transactionCount: visible.transactions,
            attachmentCount: visible.attachments,
            fingerprint: written.fingerprint,
        )
        catalog.records.append(record)
        catalog.lastFailure = nil
        let pruned = kind == .automatic ? BackupPolicy.automaticBackupsToPrune(in: catalog) : []
        catalog.records.removeAll { record in pruned.contains { $0.id == record.id } }
        do {
            try storage.saveCatalog(catalog)
        } catch {
            try? storage.delete(id: id)
            throw error
        }
        for old in pruned {
            try? storage.delete(id: old.id)
        }
        return record
    }
}

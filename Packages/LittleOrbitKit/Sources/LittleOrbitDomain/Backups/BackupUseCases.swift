import Foundation

// The backup use cases (#40). View models depend only on these protocols. `BackupService` implements them over
// `LedgerBackupSource`, `BackupStorage` and `BackupHashing`, which the App target wires in.

/// What Settings > Backups shows.
public struct BackupOverview: Equatable, Sendable {
    /// Newest first (S30).
    public var backups: [BackupRecord]
    public var lastFailure: BackupFailure?
    /// How many automatic backups are kept, for the footer (D195.4).
    public var retention: BackupRetention

    public init(
        backups: [BackupRecord] = [],
        lastFailure: BackupFailure? = nil,
        retention: BackupRetention = .default,
    ) {
        self.backups = backups
        self.lastFailure = lastFailure
        self.retention = retention
    }

    /// The newest backup of any kind, for the "Last backup" line.
    public var lastBackup: BackupRecord? {
        backups.first
    }
}

/// A backup as one `.littleorbit-backup` file, ready to save where the user chooses (D195.7). The view model names
/// it from `record`.
public struct BackupExport: Equatable, Sendable {
    /// The archive, alone in a folder of its own in the staging folder, never in the Backups folder (B2). It's
    /// removed by `discardExport`, or at the next launch if the app stopped first.
    public var file: URL
    public var record: BackupRecord

    public init(file: URL, record: BackupRecord) {
        self.file = file
        self.record = record
    }

    /// `name` as the file's name when it's one plain file name, otherwise `<backup id>.littleorbit-backup`.
    static func fileName(_ name: String, id: UUID) -> String {
        let plain = !name.isEmpty && !name.contains("/") && name != "." && name != ".." && !name.hasPrefix(".")
        return plain ? name : "\(id.uuidString).\(BackupFormat.fileExtension)"
    }
}

/// A backup to restore: one in the list, or an exported `.littleorbit-backup` file the user picked.
public enum BackupSource: Equatable, Sendable {
    case stored(UUID)
    case archive(BackupArchiveSource)

    /// A picked file, read where it is: streamed, never loaded whole (B1.1).
    public static func file(at url: URL) -> BackupSource {
        .archive(.file(url))
    }

    /// An archive already in memory.
    public static func file(_ data: Data) -> BackupSource {
        .archive(.data(data))
    }
}

/// What a change to N or M deletes now (D195.5). Made before anything is deleted, so the confirmation can show the
/// exact count.
public struct BackupCleanupPlan: Equatable, Sendable {
    public var retention: BackupRetention
    /// The backups it deletes, oldest first. Empty when the change deletes nothing.
    public var backups: [BackupRecord]

    public init(retention: BackupRetention, backups: [BackupRecord] = []) {
        self.retention = retention
        self.backups = backups
    }
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
    /// Every backup folder, newest first, each restorable, damaged or of a newer format (D195.3, D196.3, D197.2).
    func overview() async throws -> BackupOverview
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
    func deleteBackup(id: UUID) async throws
}

@MainActor
public protocol ExportBackupUseCase {
    /// The file for one restorable backup, checked first. Format 1 files aren't encrypted (D182). A damaged or
    /// newer-format backup throws `damaged` or `newerFormat` (D196.3, D197.2).
    /// The file is written in chunks and named `name`, alone in a folder of its own that only it uses (B2).
    func exportBackup(id: UUID, named name: String) async throws -> BackupExport
    /// Removes the export's file and its folder, once the save panel or share sheet closes, saved or not, and
    /// releases the export's lock on its backup. Safe to call more than once.
    func discardExport(_ export: BackupExport)
    /// How many exports of the backup are open now, in every window: from Export until `discardExport`, so through
    /// the save panel. Observable, so a window that reads it updates when an export starts or ends; Delete is off
    /// while it's above zero (D208.1).
    func exportCount(of id: UUID) -> Int
}

extension ExportBackupUseCase {
    /// `exportBackup(id:named:)`, named by the backup's ID.
    public func exportBackup(id: UUID) async throws -> BackupExport {
        try await exportBackup(id: id, named: "\(id.uuidString).\(BackupFormat.fileExtension)")
    }
}

@MainActor
public protocol BackupRetentionUseCase {
    /// The current N and M (D195.4).
    func retention() -> BackupRetention
    /// What changing to `retention` would delete now, with every backup checked first: damaged and newer-format
    /// backups are never in it, and a restorable backup is always left (L32, L33, L36). Changes nothing.
    func cleanupPlan(for retention: BackupRetention) async throws -> BackupCleanupPlan
    /// Saves the plan's N and M, then deletes the plan's backups that are still not kept. Never more than it
    /// counted (L13). Returns the backups deleted.
    func apply(_ plan: BackupCleanupPlan) async throws -> [BackupRecord]
}

@MainActor
public protocol RestoreBackupUseCase {
    /// Reads and checks a backup without writing anything or keeping its files, the format version first (D197.1,
    /// D197a.1): a stored folder file by file, a picked file in one streamed pass after the manifest, with every
    /// file hashed in chunks (B1). Returns what the Restore warning names. Throws `damaged` or `newerFormat`.
    func checkBackup(_ source: BackupSource) async throws -> BackupManifest
    /// Makes a Before restore backup of the current data, then reads `source` again, checks it and replaces all
    /// data with it in one save. If any step fails, the data is unchanged; if the Before restore backup can't be
    /// made or isn't restorable, it throws `beforeRestoreFailed` before reading `source` (D63, B3, Tester F3). Returns the Before restore
    /// backup.
    func restore(
        _ source: BackupSource,
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
    public var retention: any BackupRetentionUseCase
    public var authentication: any AppAuthenticationUseCase

    public init(
        list: any ListBackupsUseCase,
        make: any MakeBackupUseCase,
        delete: any DeleteBackupUseCase,
        export: any ExportBackupUseCase,
        restore: any RestoreBackupUseCase,
        retention: any BackupRetentionUseCase,
        authentication: any AppAuthenticationUseCase,
    ) {
        self.list = list
        self.make = make
        self.delete = delete
        self.export = export
        self.restore = restore
        self.retention = retention
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
            retention: service,
            authentication: authentication,
        )
    }
}

/// Every backup use case, as one type the composition root can hand out.
public typealias AllBackupUseCases = ListBackupsUseCase & MakeBackupUseCase & DeleteBackupUseCase
    & ExportBackupUseCase & RestoreBackupUseCase & BackupRetentionUseCase

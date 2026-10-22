import Foundation

/// How a backup came to exist (D62, D63).
public enum BackupKind: String, CaseIterable, Sendable, Codable {
    /// At most one per local calendar day, at launch or when the app goes to the background. 14 are kept.
    case automatic
    /// 'Back Up Now'. Never pruned automatically.
    case manual
    /// Made just before a restore replaces the data. Never pruned automatically.
    case beforeRestore
}

/// One stored backup, as the backup list shows it. The file itself is stored by `id`, never by its name (D173.11).
public struct BackupRecord: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var kind: BackupKind
    /// The creation moment. Stored as an absolute time and shown in the device's current time zone (D133).
    public var createdAt: Date
    /// 1 for the plain name, 2 for ' 2' and so on: fixed when the backup is made and never changed (D173.11, D174).
    public var nameIndex: Int
    public var formatVersion: Int
    /// The stored file's size in bytes, attachments included (D116.5).
    public var byteSize: Int64
    public var accountCount: Int
    public var transactionCount: Int
    public var attachmentCount: Int
    /// Identifies the ledger the backup holds, to tell whether it still reflects the current data (D116.3).
    public var fingerprint: String

    public init(
        id: UUID = UUID(),
        kind: BackupKind,
        createdAt: Date,
        nameIndex: Int = 1,
        formatVersion: Int = BackupFormat.currentVersion,
        byteSize: Int64 = 0,
        accountCount: Int = 0,
        transactionCount: Int = 0,
        attachmentCount: Int = 0,
        fingerprint: String = "",
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.nameIndex = nameIndex
        self.formatVersion = formatVersion
        self.byteSize = byteSize
        self.accountCount = accountCount
        self.transactionCount = transactionCount
        self.attachmentCount = attachmentCount
        self.fingerprint = fingerprint
    }
}

/// Why the last backup failed. It stays until the next successful backup.
public enum BackupFailure: String, Sendable, Codable, Equatable {
    case notEnoughStorage
}

/// What the app keeps next to its backup files: the list, the last failure and the restored state.
public struct BackupCatalog: Equatable, Sendable, Codable {
    public var records: [BackupRecord]
    public var lastFailure: BackupFailure?
    /// The fingerprint of the data a restore left in place. That state counts as reflected, so no automatic
    /// backup runs until the first data change after the restore (D96.3, D118.2).
    public var restoredFingerprint: String?

    public init(records: [BackupRecord] = [], lastFailure: BackupFailure? = nil, restoredFingerprint: String? = nil) {
        self.records = records
        self.lastFailure = lastFailure
        self.restoredFingerprint = restoredFingerprint
    }

    /// Newest first by the stored creation time, never by the file name (S30, D179.4): after a time-zone change
    /// two names can show the same time, but the order stays right.
    public var newestFirst: [BackupRecord] {
        records.sorted { ($0.createdAt, $0.nameIndex) > ($1.createdAt, $1.nameIndex) }
    }
}

/// Errors a backup, export or restore can end with. Each leaves the current data unchanged.
public enum BackupError: Error, Equatable, Sendable {
    /// Not a backup, truncated, or its checksum fails: 'This Backup Is Damaged' (D63).
    case damaged
    /// Made by a newer version of the app: 'Update little-orbit to Restore This Backup' (D63).
    case newerFormat
    /// The file is encrypted and no password was given yet.
    case passwordRequired
    /// 'Incorrect password. Try again.' (D118.4). Retries are unlimited.
    case incorrectPassword
    /// No partial file is kept and nothing is pruned (D62).
    case notEnoughStorage
    /// Another backup or restore is running. Actions are disabled, not queued (D118.5).
    case busy
    /// The backup isn't in the list any more.
    case notFound
    /// Encryption isn't available on this platform (Linux test runs).
    case encryptionUnavailable
    /// `catalog.json` can't be read. The service rebuilds the list from the stored files.
    case catalogUnreadable
}

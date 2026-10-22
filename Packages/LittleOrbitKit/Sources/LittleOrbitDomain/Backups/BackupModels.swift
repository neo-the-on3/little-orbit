import Foundation

/// How a backup came to exist (D62, D63).
public enum BackupKind: String, CaseIterable, Sendable, Codable {
    /// At most one per local calendar day, at launch or when the app goes to the background. Pruned by
    /// `BackupRetention` (D195.4).
    case automatic
    /// 'Back Up Now'. Never pruned automatically.
    case manual
    /// Made just before a restore replaces the data. Never pruned automatically.
    case beforeRestore
}

/// Whether a backup in the list can be restored (D196.3, D197.2).
public enum BackupCondition: String, Sendable, Codable, Equatable {
    /// A supported format whose files were found as its manifest lists them. Only these count for retention and
    /// for the rule that cleanup never deletes the only restorable backup (L33, L43).
    case restorable
    /// Its manifest is missing or unreadable, or a listed file is missing or fails its checksum. Listed as
    /// 'Damaged'; never pruned and never counted (D196.3, L29–L33).
    case damaged
    /// Made by a newer version of little-orbit. Never checksum-checked, never 'Damaged', never pruned or counted
    /// (D197.2, L35, L36).
    case newerFormat
}

/// One stored backup, as the backup list shows it. Its folder is named by `id`, never by its name (D173.11, D195.1).
public struct BackupRecord: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    /// `nil` only for a damaged folder whose manifest was never read, so its kind isn't known.
    public var kind: BackupKind?
    /// The creation moment. Stored as an absolute time and shown in the device's current time zone (D133).
    /// `BackupRecord.unknownDate` for a damaged folder with no readable date, so it sorts last (D202.1, L49).
    public var createdAt: Date
    /// 1 for the plain name, 2 for ' 2' and so on: fixed when the backup is made and never changed (D173.11, D174).
    public var nameIndex: Int
    /// 0 when it isn't known (a folder without a readable manifest).
    public var formatVersion: Int
    /// The manifest total in bytes, attachments included: the same as the exported size (D116.5, S61, D195). For a
    /// damaged folder whose manifest was never read, the total of its files' sizes; `nil` when that can't be
    /// computed (D202.1, L48, L49).
    public var byteSize: Int64?
    public var accountCount: Int
    public var transactionCount: Int
    public var attachmentCount: Int
    /// Identifies the ledger the backup holds, to tell whether it still reflects the current data (D116.3).
    public var fingerprint: String
    /// `YYYY-MM` in the device's time zone when the backup was made, from the manifest (D196.2). `nil` when the
    /// manifest has none; cleanup then uses `createdAt` in the current zone (L28).
    public var month: String?
    public var condition: BackupCondition

    public init(
        id: UUID = UUID(),
        kind: BackupKind?,
        createdAt: Date,
        nameIndex: Int = 1,
        formatVersion: Int = BackupFormat.currentVersion,
        byteSize: Int64? = 0,
        accountCount: Int = 0,
        transactionCount: Int = 0,
        attachmentCount: Int = 0,
        fingerprint: String = "",
        month: String? = nil,
        condition: BackupCondition = .restorable,
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
        self.month = month
        self.condition = condition
    }

    /// Restore… and Export… are available (D196.3, D197.2).
    public var isRestorable: Bool {
        condition == .restorable
    }
}

/// Why the last backup failed. It stays until the next successful backup.
public enum BackupFailure: String, Sendable, Codable, Equatable {
    case notEnoughStorage
}

/// What the app keeps about its backups besides the folders: the last failure, the restored state, and a cache of
/// what each folder's manifest said and how its last check went. The list itself always comes from the folders
/// (D195.3); the cache only lets a folder whose manifest went missing still show its kind and date (L29), and keeps
/// a failed checksum check until the next check passes (D196.3).
public struct BackupStatus: Equatable, Sendable, Codable {
    public var lastFailure: BackupFailure?
    /// The fingerprint of the data a restore left in place. That state counts as reflected, so no automatic
    /// backup runs until the first data change after the restore (D96.3, D118.2).
    public var restoredFingerprint: String?
    /// The last record built for each folder, by ID. Rebuilt from the folders on every list.
    public var known: [UUID: BackupRecord]

    public init(
        lastFailure: BackupFailure? = nil,
        restoredFingerprint: String? = nil,
        known: [UUID: BackupRecord] = [:],
    ) {
        self.lastFailure = lastFailure
        self.restoredFingerprint = restoredFingerprint
        self.known = known
    }

    private enum CodingKeys: String, CodingKey {
        case lastFailure, restoredFingerprint, known
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastFailure = try container.decodeIfPresent(BackupFailure.self, forKey: .lastFailure)
        restoredFingerprint = try container.decodeIfPresent(String.self, forKey: .restoredFingerprint)
        let records = try container.decodeIfPresent([BackupRecord].self, forKey: .known) ?? []
        known = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastFailure, forKey: .lastFailure)
        try container.encodeIfPresent(restoredFingerprint, forKey: .restoredFingerprint)
        try container.encode(known.values.sorted { $0.id.uuidString < $1.id.uuidString }, forKey: .known)
    }
}

/// The backups that exist, built from their folders, with the status next to them.
public struct BackupCatalog: Equatable, Sendable {
    public var records: [BackupRecord]
    public var lastFailure: BackupFailure?
    public var restoredFingerprint: String?

    public init(records: [BackupRecord] = [], lastFailure: BackupFailure? = nil, restoredFingerprint: String? = nil) {
        self.records = records
        self.lastFailure = lastFailure
        self.restoredFingerprint = restoredFingerprint
    }

    public init(records: [BackupRecord], status: BackupStatus) {
        self.init(
            records: records,
            lastFailure: status.lastFailure,
            restoredFingerprint: status.restoredFingerprint,
        )
    }

    /// Only the backups that can be restored: the ones the automatic-backup rules look at (D196.3).
    public var restorable: BackupCatalog {
        BackupCatalog(
            records: records.filter(\.isRestorable),
            lastFailure: lastFailure,
            restoredFingerprint: restoredFingerprint,
        )
    }

    /// Newest first by the stored creation time, never by the file name (S30, D179.4): after a time-zone change
    /// two names can show the same time, but the order stays right.
    public var newestFirst: [BackupRecord] {
        records.sorted { ($0.createdAt, $0.nameIndex) > ($1.createdAt, $1.nameIndex) }
    }
}

extension BackupRecord {
    /// The date of a damaged folder whose creation date can't be read: before every real date, so the row sorts
    /// last, and shown as "Unknown", never as a date (D202.1, L49).
    public static let unknownDate = Date.distantPast

    /// Whether `createdAt` is a real date.
    public var isDateKnown: Bool {
        createdAt != Self.unknownDate
    }
}

/// Errors a backup, export or restore can end with. Each leaves the current data unchanged.
public enum BackupError: Error, Equatable, Sendable {
    /// Not a backup, truncated, or its checksum fails: 'This Backup Is Damaged' (D63).
    case damaged
    /// Made by a newer version of the app: 'Update little-orbit to Restore This Backup' (D63).
    case newerFormat
    /// No partial folder is kept and nothing is pruned (D62, D195.6).
    case notEnoughStorage
    /// Another backup or restore is running. Actions are disabled, not queued (D118.5).
    case busy
    /// The backup isn't in the list any more.
    case notFound
}

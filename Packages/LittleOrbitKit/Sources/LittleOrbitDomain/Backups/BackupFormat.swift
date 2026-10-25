import Foundation

/// Format 1 of a little-orbit backup (D195). See docs/backup-format.md.
///
/// Each backup is one self-contained folder, named by its ID, that never refers to anything outside itself:
/// - `manifest.json`: the format, its version, what the backup is, and the path, size and SHA-256 of every other
///   file. It's written last, so a folder without a valid manifest is never a backup.
/// - `shared.json`: the ledger data that isn't per account and per year.
/// - `transfers/<year>.json`: transfers, by the year of their own local date.
/// - `accounts/<account id>/<year>.json`: every other transaction, by account and year.
/// - `attachments/<attachment id>`: attachment bytes.
///
/// Format 1 is never encrypted (D182). A format-1 manifest with an `encryption` key is damaged; encryption can
/// come later as a format bump. An exported backup is the same folder in one uncompressed Apple Archive (D195a.1).
///
/// `manifest.json`, at the root of the folder, and its `format` and `formatVersion` fields keep their names and
/// place in every future format, so any version of the app can read the version first and refuse a newer one
/// (D197.1, L38).
public enum BackupFormat {
    public static let identifier = "little-orbit-backup"
    /// The exported single file (D195.7).
    public static let fileExtension = "littleorbit-backup"
    /// The suffix of an export's own folder in the staging folder (B2).
    public static let exportFolderSuffix = ".export"

    /// Removes `file` and the export folder it's in, when its folder is one (`<uuid>.export`). Nothing else is
    /// removed.
    public static func removeExport(_ file: URL) {
        let folder = file.deletingLastPathComponent()
        let name = folder.lastPathComponent
        guard name.hasSuffix(exportFolderSuffix),
            UUID(uuidString: String(name.dropLast(exportFolderSuffix.count))) != nil
        else {
            return
        }
        try? FileManager.default.removeItem(at: folder)
    }
    /// The exported type the apps declare, conforming to `public.data` (D195a.1, L19).
    public static let typeIdentifier = "app.littleorbit.backup"
    public static let currentVersion = 1

    public static let manifestPath = "manifest.json"
    public static let sharedPath = "shared.json"
    public static let attachmentsFolder = "attachments"
    public static let transfersFolder = "transfers"
    public static let accountsFolder = "accounts"

    /// Whether `path` is a relative path that stays inside a backup folder: not empty, not absolute, and with no
    /// empty, `.` or `..` component (D195.2, L3).
    public static func isContained(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { part in
                !part.isEmpty && part != "." && part != ".."
            }
    }
}

/// The files of one backup folder, by relative path (`accounts/<id>/2026.json`). Paths use `/`.
public struct BackupSnapshotFiles: Equatable, Sendable {
    public var files: [String: Data]

    public init(_ files: [String: Data] = [:]) {
        self.files = files
    }

    public subscript(path: String) -> Data? {
        get { files[path] }
        set { files[path] = newValue }
    }

    /// Every path, sorted.
    public var paths: [String] {
        files.keys.sorted()
    }
}

/// One file the manifest lists.
public struct BackupFileEntry: Equatable, Sendable, Codable {
    public var sha256: String
    public var byteSize: Int64

    public init(sha256: String, byteSize: Int64) {
        self.sha256 = sha256
        self.byteSize = byteSize
    }
}

/// The sections a backup holds (D62, D96). Sections for features that haven't shipped are reserved: format 1
/// writes them empty. Budgets (#25) fill theirs within format 1 while the schema is still V1 in development
/// (D294): a backup without budgets reads as before. After the first release, filling a section bumps
/// `BackupFormat.currentVersion` and migrates older files.
public enum BackupSection: String, CaseIterable, Sendable, Codable {
    case accounts
    case transactions
    case categories
    case payees
    case tags
    case splits
    case attachments
    /// Listed in the manifest only when the backup has budgets (#25).
    case budgets
    // Reserved until their tickets ship. #40 doesn't wait for them.
    case importRules
    case scheduledItems
    case reconciliationHistory
    case sharedSettings

    /// Sections whose data exists in format 1.
    public static let populated: [BackupSection] = [
        .accounts, .transactions, .categories, .payees, .tags, .splits, .attachments,
    ]
}

/// What a backup describes about itself. Readable without restoring.
public struct BackupManifest: Equatable, Sendable, Codable {
    public var formatVersion: Int
    public var kind: BackupKind
    public var createdAt: Date
    public var nameIndex: Int
    /// The SwiftData schema the data came from, e.g. "1.0.0".
    public var schemaVersion: String
    public var accountCount: Int
    public var transactionCount: Int
    public var attachmentCount: Int
    /// The sections with data. Reserved sections are listed only once they carry data.
    public var sections: [BackupSection]
    /// `YYYY-MM` in the device's time zone when the backup was made. Cleanup uses it as the backup's month and
    /// never recomputes it (D196.2, L26, L27).
    public var month: String?
    /// The backup's identity, which the export lock, the selection, the status cache and the Before restore backup
    /// use. Its folder's name is only when it was made, and is never read back (D209). `nil` in manifests from
    /// earlier builds, whose folders are named by this ID.
    public var id: UUID?

    public init(
        formatVersion: Int = BackupFormat.currentVersion,
        kind: BackupKind,
        createdAt: Date,
        nameIndex: Int,
        schemaVersion: String,
        accountCount: Int,
        transactionCount: Int,
        attachmentCount: Int,
        sections: [BackupSection] = BackupSection.populated,
        month: String? = nil,
        id: UUID? = nil,
    ) {
        self.formatVersion = formatVersion
        self.kind = kind
        self.createdAt = createdAt
        self.nameIndex = nameIndex
        self.schemaVersion = schemaVersion
        self.accountCount = accountCount
        self.transactionCount = transactionCount
        self.attachmentCount = attachmentCount
        self.sections = sections
        self.month = month
        self.id = id
    }
}

/// A record of a feature that hasn't shipped yet. Format 1 always writes these sections as empty arrays.
public struct BackupReservedRecord: Equatable, Sendable, Codable {
    public init() {}
}

/// Shared (synced) settings that go in every backup (D96.1). None of them exist yet, so format 1 leaves every
/// field empty. Per-device settings (app lock, hide amounts, report exclusions, theme, reconciliation drafts) are
/// never part of a backup (D23, D62), so there's no field for them.
public struct BackupSharedSettings: Equatable, Sendable, Codable {
    public var newTransactionsDefaultToPending: Bool?
    public var tagsEnabled: Bool?
    public var defaultTagID: UUID?
    public var defaultCurrencyCode: String?
    public var showUpcoming: Bool?

    public init(
        newTransactionsDefaultToPending: Bool? = nil,
        tagsEnabled: Bool? = nil,
        defaultTagID: UUID? = nil,
        defaultCurrencyCode: String? = nil,
        showUpcoming: Bool? = nil,
    ) {
        self.newTransactionsDefaultToPending = newTransactionsDefaultToPending
        self.tagsEnabled = tagsEnabled
        self.defaultTagID = defaultTagID
        self.defaultCurrencyCode = defaultCurrencyCode
        self.showUpcoming = showUpcoming
    }
}

/// Everything inside a backup's body.
public struct BackupContents: Equatable, Sendable, Codable {
    public var manifest: BackupManifest
    public var accounts: [Account]
    public var transactions: [Transaction]
    public var categories: [TransactionCategory]
    public var payees: [Payee]
    public var tags: [Tag]
    public var splits: [TransactionSplit]
    /// Attachments with their bytes (D19).
    public var attachments: [Attachment]
    public var importRules: [BackupReservedRecord]
    /// Budgets with their limit history (#25). Empty in backups made before budgets.
    public var budgets: [Budget]
    public var scheduledItems: [BackupReservedRecord]
    public var reconciliationHistory: [BackupReservedRecord]
    public var sharedSettings: BackupSharedSettings

    public init(manifest: BackupManifest, ledger: LedgerSnapshot, sharedSettings: BackupSharedSettings = .init()) {
        self.manifest = manifest
        let ordered = BackupContents.canonical(ledger)
        accounts = ordered.accounts
        transactions = ordered.transactions
        categories = ordered.categories
        payees = ordered.payees
        tags = ordered.tags
        splits = ordered.splits
        attachments = ordered.attachments
        importRules = []
        budgets = ordered.budgets
        if !budgets.isEmpty && !self.manifest.sections.contains(.budgets) {
            self.manifest.sections.append(.budgets)
        }
        scheduledItems = []
        reconciliationHistory = []
        self.sharedSettings = sharedSettings
    }

    /// The ledger this backup restores, soft-deleted records included, so a restore is exact.
    public var ledger: LedgerSnapshot {
        LedgerSnapshot(
            accounts: accounts,
            transactions: transactions,
            categories: categories,
            payees: payees,
            tags: tags,
            splits: splits,
            attachments: attachments,
            budgets: budgets,
        )
    }

    /// Records sorted by ID, so the same data always encodes to the same bytes and fingerprint.
    public static func canonical(_ ledger: LedgerSnapshot) -> LedgerSnapshot {
        LedgerSnapshot(
            accounts: ledger.accounts.sorted { $0.id.uuidString < $1.id.uuidString },
            transactions: ledger.transactions.sorted { $0.id.uuidString < $1.id.uuidString },
            categories: ledger.categories.sorted { $0.id.uuidString < $1.id.uuidString },
            payees: ledger.payees.sorted { $0.id.uuidString < $1.id.uuidString },
            tags: ledger.tags.sorted { $0.id.uuidString < $1.id.uuidString },
            splits: ledger.splits.sorted { $0.id.uuidString < $1.id.uuidString },
            attachments: ledger.attachments.sorted { $0.id.uuidString < $1.id.uuidString },
            budgets: ledger.budgets.sorted { $0.id.uuidString < $1.id.uuidString },
        )
    }
}

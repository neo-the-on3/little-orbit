import Foundation

/// The `.littleorbit-backup` file format. See docs/backup-format.md.
///
/// A file is a JSON envelope:
/// - `format`: always `little-orbit-backup`
/// - `formatVersion`: the version of the contents. A newer one than `currentVersion` can't be restored (D63).
/// - `checksum`: SHA-256 (hex) of the `body` bytes
/// - `encryption`: absent for a plain file, otherwise how the body was sealed with the export password
/// - `body`: base64 of the UTF-8 JSON `BackupContents`, or of its AES-GCM sealed box when encrypted
public enum BackupFormat {
    public static let identifier = "little-orbit-backup"
    public static let fileExtension = "littleorbit-backup"
    public static let currentVersion = 1
}

/// How an exported body was encrypted with its password (D63, D96).
public struct BackupEncryption: Equatable, Sendable, Codable {
    public static let aesGCM = "AES-256-GCM"
    public static let pbkdf2 = "PBKDF2-HMAC-SHA256"
    /// The iteration counts a file may claim. Anything outside is reported as damaged, so a crafted file can't
    /// crash the key derivation or tie up the CPU for hours.
    public static let allowedIterations = 100_000...10_000_000

    public var algorithm: String
    public var keyDerivation: String
    public var iterations: Int
    public var salt: Data

    public init(
        algorithm: String = BackupEncryption.aesGCM,
        keyDerivation: String = BackupEncryption.pbkdf2,
        iterations: Int,
        salt: Data,
    ) {
        self.algorithm = algorithm
        self.keyDerivation = keyDerivation
        self.iterations = iterations
        self.salt = salt
    }

    /// Whether these are parameters this version can open: AES-256-GCM, PBKDF2-HMAC-SHA256, a count in
    /// `allowed` and a 16-byte salt.
    public func isSupported(allowedIterations allowed: ClosedRange<Int> = BackupEncryption.allowedIterations) -> Bool {
        algorithm == Self.aesGCM && keyDerivation == Self.pbkdf2 && allowed.contains(iterations) && salt.count == 16
    }
}

/// The sections a backup holds (D62, D96). Sections for features that haven't shipped are reserved: format 1
/// writes them empty, and the version that fills one bumps `BackupFormat.currentVersion` and migrates older files.
public enum BackupSection: String, CaseIterable, Sendable, Codable {
    case accounts
    case transactions
    case categories
    case payees
    case tags
    case splits
    case attachments
    // Reserved until their tickets ship. #40 doesn't wait for them.
    case importRules
    case budgets
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
    public var budgets: [BackupReservedRecord]
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
        budgets = []
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
        )
    }
}

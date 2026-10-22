import Foundation

/// The ledger as a whole, for backups. Implemented by the repositories in `LittleOrbitPersistence`.
@MainActor
public protocol LedgerBackupSource: AnyObject {
    /// Every record, soft-deleted ones included.
    func ledgerSnapshot() throws -> LedgerSnapshot
    /// Replaces all data with `snapshot` in one save: it either completes fully or changes nothing (D63).
    func replaceLedger(with snapshot: LedgerSnapshot) throws
}

/// What a backup folder holds, as the list reads it: its manifest, if there is one, and the size of each file.
public struct BackupFolderListing: Equatable, Sendable {
    /// `nil` when the folder has no `manifest.json` (D196.3).
    public var manifest: Data?
    /// Every regular file in the folder by relative path, the manifest included.
    public var fileSizes: [String: Int64]
    /// When the folder was made, for a damaged folder whose manifest was never read.
    public var createdAt: Date?

    public init(manifest: Data?, fileSizes: [String: Int64], createdAt: Date? = nil) {
        self.manifest = manifest
        self.fileSizes = fileSizes
        self.createdAt = createdAt
    }
}

/// Where backup folders live: the app's own container, under system data protection, never the App Group or
/// anywhere uploaded (D62, D195). Implemented in `LittleOrbitPersistence`. Safe to call off the main actor.
public protocol BackupStorage: Sendable {
    /// The IDs of every folder in the Backups folder that's named by a backup ID, with or without a manifest: one
    /// without is a damaged backup, not a leftover (D196.3, D197.4). Folders still being built are elsewhere and are
    /// never listed (D195.6).
    func storedIDs() throws -> [UUID]
    /// A folder's manifest and file sizes, for the list. Throws `BackupError.notFound` when the folder is gone, and
    /// the underlying error for a failed read (R3).
    func listing(id: UUID) throws -> BackupFolderListing
    /// Every file in a backup folder, by relative path, all in memory. Only export uses it; checks and restores
    /// read through `files(id:)`.
    func read(id: UUID) throws -> BackupSnapshotFiles
    /// A backup folder's files, read one at a time when asked, so a check never holds the whole backup (Tech
    /// Architect's B1.2). Throws `BackupError.notFound` when the folder is gone.
    func files(id: UUID) throws -> any BackupFileReading
    /// Builds the folder in a temporary place outside the Backups folder, `manifest.json` last, then renames it into
    /// place, so it only exists there once it's complete (D195.6, D196.3). A file that's byte-for-byte the same in
    /// backup `cloningFrom` may be an APFS clone of it; it's always a separate file (D195.1). Throws
    /// `BackupError.notEnoughStorage` when the disk is full, leaving no folder.
    func write(_ files: BackupSnapshotFiles, id: UUID, cloningFrom earlier: UUID?) throws
    /// Removes the whole folder. It stops being listed before any of its files are removed (L17).
    func delete(id: UUID) throws
    func loadStatus() throws -> BackupStatus
    func saveStatus(_ status: BackupStatus) throws
}

extension BackupStorage {
    /// The whole folder in memory, for stores that have nothing better.
    public func files(id: UUID) throws -> any BackupFileReading {
        try read(id: id)
    }
}

/// A backup folder's files by relative path, read one at a time: a stored folder, or files already in memory.
public protocol BackupFileReading {
    /// The whole file, or `nil` when it isn't there as a regular file.
    func data(at path: String) throws -> Data?
    /// Hands the file to `body` in chunks, in order, never holding it whole. `false` when it isn't there as a
    /// regular file.
    func stream(_ path: String, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool
}

extension BackupSnapshotFiles: BackupFileReading {
    public func data(at path: String) throws -> Data? {
        self[path]
    }

    public func stream(_ path: String, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        guard let data = self[path] else {
            return false
        }
        try data.withUnsafeBytes(body)
        return true
    }
}

/// The backup settings of this device (D195.4). They're app settings, not ledger data: a backup doesn't hold
/// them and a restore doesn't change them. Implemented over `UserDefaults` in `LittleOrbitPersistence`.
public protocol BackupSettingsStore: Sendable {
    func retention() -> BackupRetention
    func setRetention(_ retention: BackupRetention)
}

/// Checksums for backup files and ledger fingerprints. Implemented with CryptoKit in `LittleOrbitPersistence`.
public protocol BackupHashing: Sendable {
    /// SHA-256 of `data`, as lowercase hex.
    func sha256Hex(_ data: Data) -> String
    /// An incremental SHA-256, so a large file is hashed in chunks instead of read whole (B1).
    func makeDigest() -> any BackupDigest
}

/// One incremental SHA-256: `update` with each chunk in order, then `finish` once.
public protocol BackupDigest: AnyObject {
    func update(_ bytes: UnsafeRawBufferPointer)
    /// The SHA-256 of every chunk so far, as lowercase hex.
    func finish() -> String
}

/// Why the app asks the user to authenticate.
public enum AppAuthenticationPurpose: Sendable, Equatable {
    case restoreBackup
    case exportBackup
    case deleteBackup
    /// Lowering N or M deletes backups (D195.5).
    case pruneBackups
}

/// How the device unlocks: its biometry, or only the app passcode. Neutral device data from the App target.
public enum AppUnlockMethod: Sendable, Equatable {
    case faceID
    case touchID
    case opticID
    /// No biometry, or biometry not set up: only the app passcode.
    case passcodeOnly
}

/// The App Lock check before Restore, Export, Delete and a confirmed cleanup (D20, D63, S31, S51, S64, D195.5).
///
/// #29 builds App Lock and implements this. Until then `AppLockOff` is wired in, which always allows the action.
@MainActor
public protocol AppAuthenticationUseCase {
    /// `true` when App Lock is off or the user authenticated; `false` when they cancelled or failed, in which
    /// case nothing changes.
    func authenticate(for purpose: AppAuthenticationPurpose) async -> Bool
    /// The device's unlock method, for the Delete footnote.
    func unlockMethod() -> AppUnlockMethod
}

/// App Lock isn't built yet (#29): every action is allowed without a prompt.
public struct AppLockOff: AppAuthenticationUseCase {
    private let method: AppUnlockMethod

    public init(unlockMethod: AppUnlockMethod = .passcodeOnly) {
        method = unlockMethod
    }

    public func authenticate(for purpose: AppAuthenticationPurpose) async -> Bool {
        true
    }

    public func unlockMethod() -> AppUnlockMethod {
        method
    }
}

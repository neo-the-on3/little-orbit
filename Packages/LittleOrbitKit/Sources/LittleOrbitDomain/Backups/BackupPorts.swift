import Foundation

/// The ledger as a whole, for backups. Implemented by the repositories in `LittleOrbitPersistence`.
@MainActor
public protocol LedgerBackupSource: AnyObject {
    /// Every record, soft-deleted ones included.
    func ledgerSnapshot() throws -> LedgerSnapshot
    /// Replaces all data with `snapshot` in one save: it either completes fully or changes nothing (D63).
    func replaceLedger(with snapshot: LedgerSnapshot) throws
}

/// Where backup files and their list live: the app's own container, under system data protection, never the App
/// Group or anywhere uploaded (D62). Implemented in `LittleOrbitPersistence`. Safe to call off the main actor.
public protocol BackupStorage: Sendable {
    func loadCatalog() throws -> BackupCatalog
    func saveCatalog(_ catalog: BackupCatalog) throws
    /// Writes the whole file or nothing, and returns its size in bytes. Throws `BackupError.notEnoughStorage`
    /// when the disk is full, leaving no partial file.
    func write(_ data: Data, id: UUID) throws -> Int64
    func read(id: UUID) throws -> Data
    func delete(id: UUID) throws
    /// The IDs of every stored backup file, to rebuild an unreadable catalog.
    func storedIDs() throws -> [UUID]
}

/// Checksums and export encryption. Implemented with CryptoKit in `LittleOrbitPersistence`.
public protocol BackupCryptography: Sendable {
    /// SHA-256 of `data`, as lowercase hex.
    func sha256Hex(_ data: Data) -> String
    /// Fresh parameters for one export: the iteration count and a random 16-byte salt.
    func makeEncryption() -> BackupEncryption
    /// Encrypts `plaintext` with a key derived from `password` (NFC-normalised), binding `header` as
    /// authenticated data so the file's header can't be changed without failing to open.
    func seal(_ plaintext: Data, password: String, encryption: BackupEncryption, header: Data) throws -> Data
    /// Decrypts. Throws `BackupError.incorrectPassword` when the password doesn't open it or the header changed,
    /// and `BackupError.damaged` for parameters it doesn't support.
    func open(_ sealed: Data, password: String, encryption: BackupEncryption, header: Data) throws -> Data
}

/// Why the app asks the user to authenticate.
public enum AppAuthenticationPurpose: Sendable, Equatable {
    case restoreBackup
    case exportBackup
    case deleteBackup
}

/// How the device unlocks: its biometry, or only the app passcode. Neutral device data from the App target.
public enum AppUnlockMethod: Sendable, Equatable {
    case faceID
    case touchID
    case opticID
    /// No biometry, or biometry not set up: only the app passcode.
    case passcodeOnly
}

/// The App Lock check before Restore, Export and Delete (D20, D63, S31, S51, S64).
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

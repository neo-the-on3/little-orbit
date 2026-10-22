import Foundation

/// Schema version written by this package. `LittleOrbitSchemaV1` uses the same numbers.
public enum LedgerSchemaVersion {
    public static let major = 1
    public static let minor = 0
    public static let patch = 0

    public static var description: String {
        "\(major).\(minor).\(patch)"
    }
}

/// Sync is a seam for a later phase. `.none` is the only mode, and it is the default.
public enum StoreSyncMode: String, Sendable, Equatable, Codable {
    case none
}

/// Where the ledger is stored. The default is a local file with sync off, opened for reading and writing.
public struct StoreConfiguration: Sendable, Equatable {
    public var sync: StoreSyncMode
    public var inMemory: Bool
    public var fileURL: URL?
    /// Opens the file without saving, as an extension reading the app's store does. Writes fail and leave the
    /// store unchanged.
    public var readOnly: Bool

    public init(sync: StoreSyncMode = .none, inMemory: Bool = false, fileURL: URL? = nil, readOnly: Bool = false) {
        self.sync = sync
        self.inMemory = inMemory
        self.fileURL = fileURL
        self.readOnly = readOnly
    }

    public static let local = StoreConfiguration()
    public static let inMemory = StoreConfiguration(inMemory: true)
}

public enum StoreError: Error, Equatable, Sendable {
    /// `StoreSyncMode` has no implemented sync path. CloudKit stays off until a later change.
    case syncNotImplemented
    /// The app is entitled to its App Group, but the container is missing or can't be written. The store isn't
    /// opened, so no second, empty store is created in Application Support.
    case appGroupContainerUnavailable(AppGroupContainerFailure)
    /// An extension asked for the shared store, but the build names no App Group or isn't entitled to it.
    case sharedStoreUnavailable(StoreFallbackReason)
    /// A read-only store was opened before its file exists, as when an extension runs before the app has ever
    /// created the store. Nothing is created.
    case readOnlyStoreMissing
}

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

/// Where the ledger is stored. The default is a local file with sync off.
public struct StoreConfiguration: Sendable, Equatable {
    public var sync: StoreSyncMode
    public var inMemory: Bool
    public var fileURL: URL?

    public init(sync: StoreSyncMode = .none, inMemory: Bool = false, fileURL: URL? = nil) {
        self.sync = sync
        self.inMemory = inMemory
        self.fileURL = fileURL
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
}

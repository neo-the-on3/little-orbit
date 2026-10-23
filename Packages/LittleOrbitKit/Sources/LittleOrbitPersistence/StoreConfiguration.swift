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
    /// Where the store is recorded after it opens (#52). `LittleOrbitStore.makeContainer` writes it, only for a
    /// writable file store and only when it changes. `nil` records nothing.
    public var homeRecord: StoreHomeRecord?

    public init(
        sync: StoreSyncMode = .none,
        inMemory: Bool = false,
        fileURL: URL? = nil,
        readOnly: Bool = false,
        homeRecord: StoreHomeRecord? = nil,
    ) {
        self.sync = sync
        self.inMemory = inMemory
        self.fileURL = fileURL
        self.readOnly = readOnly
        self.homeRecord = homeRecord
    }

    public static let local = StoreConfiguration()
    public static let inMemory = StoreConfiguration(inMemory: true)
}

public enum StoreError: Error, Equatable, Sendable {
    /// `StoreSyncMode` has no implemented sync path. CloudKit stays off until a later change.
    case syncNotImplemented
    /// The app is entitled to its App Group and its store is recorded there, but the container is missing or can't
    /// be written. The store isn't opened, so no second, empty store is created in Application Support. An
    /// extension also gets this when the system returns no container.
    case appGroupContainerUnavailable(AppGroupContainerFailure)
    /// The store is recorded in an App Group that this build can't use: it names no group or another one, or
    /// isn't entitled. The store isn't opened and the app folder isn't used instead.
    case storeIsInAppGroup(StoreHomeConflict)
    /// The App Group store and the app-folder store both hold data. They are never merged; #102 handles this.
    case storesInBothLocations
    /// An extension asked for the shared store, but the build names no App Group or isn't entitled to it.
    case sharedStoreUnavailable(StoreFallbackReason)
    /// An extension found no store-home copy in the group, or one that doesn't name this group's store, so there
    /// is no shared data to read. Nothing is created.
    case sharedStoreNotInGroup
    /// A read-only store was opened before its file exists, as when an extension runs before the app has ever
    /// created the store. Nothing is created.
    case readOnlyStoreMissing
}

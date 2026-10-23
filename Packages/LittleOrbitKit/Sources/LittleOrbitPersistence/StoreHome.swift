import Foundation

#if canImport(os)
    import os
#endif

/// Where the app's store lives, as recorded after a successful open (#52). `StoreLocation` reads it on the next
/// launch, so a store only moves through #102's one-time migration, never because of one bad launch.
public struct StoreHome: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// `<group container>/LittleOrbit.store`.
        case group
        /// `Application Support/<bundle id>/LittleOrbit.store`.
        case appFolder
    }

    public var kind: Kind
    /// The exact App Group identifier when `kind` is `group`, otherwise `nil`.
    public var groupIdentifier: String?
    /// The store's own identifier (`StoreIdentity`), when it could be read. For #102 and diagnostics; the location
    /// decision doesn't use it.
    public var storeID: UUID?

    public init(kind: Kind, groupIdentifier: String? = nil, storeID: UUID? = nil) {
        self.kind = kind
        self.groupIdentifier = kind == .group ? groupIdentifier : nil
        self.storeID = storeID
    }

    public static func group(_ identifier: String, storeID: UUID? = nil) -> StoreHome {
        StoreHome(kind: .group, groupIdentifier: identifier, storeID: storeID)
    }

    public static func appFolder(storeID: UUID? = nil) -> StoreHome {
        StoreHome(kind: .appFolder, storeID: storeID)
    }

    /// The same location, ignoring the store ID.
    func isSameLocation(as other: StoreHome) -> Bool {
        kind == other.kind && groupIdentifier == other.groupIdentifier
    }
}

/// What a marker store holds.
public enum StoreHomeMarkerState: Sendable, Equatable {
    /// No marker yet, as before the first successful open.
    case missing
    /// A marker that can't be read or decoded. The location can't be known from it, so the decision treats it as
    /// unknown: it never falls back on it while the group container is unavailable.
    case unreadable
    case recorded(StoreHome)
}

/// Reads and writes a store-home marker. `FileStoreHomeMarkerStore` is the app's; tests inject their own.
public protocol StoreHomeMarkerStore: Sendable {
    func read() -> StoreHomeMarkerState
    func write(_ home: StoreHome) throws
}

/// A marker kept in a JSON file, written atomically.
public struct FileStoreHomeMarkerStore: StoreHomeMarkerStore {
    public static let fileName = "StoreHome.json"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Application Support/<bundle id>/StoreHome.json`, next to the app-folder store.
    public static func appFolder(applicationSupport: URL, bundleIdentifier: String?) -> FileStoreHomeMarkerStore {
        let folder = StoreLocation.storeURL(applicationSupport: applicationSupport, bundleIdentifier: bundleIdentifier)
            .deletingLastPathComponent()
        return FileStoreHomeMarkerStore(url: folder.appendingPathComponent(fileName, isDirectory: false))
    }

    /// The best-effort copy in the App Group container that extensions read.
    public static func groupCopy(container: URL) -> FileStoreHomeMarkerStore {
        FileStoreHomeMarkerStore(url: container.appendingPathComponent(fileName, isDirectory: false))
    }

    public func read() -> StoreHomeMarkerState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        guard let data = try? Data(contentsOf: url), let home = try? JSONDecoder().decode(StoreHome.self, from: data)
        else {
            return .unreadable
        }
        return .recorded(home)
    }

    public func write(_ home: StoreHome) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// The store's own identifier: a UUID kept beside the store file (`LittleOrbit.store.id`) and created on the
/// first writable open. SwiftData has no public store metadata, and a file beside the store moves with it.
public enum StoreIdentity {
    public static func url(forStoreAt storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + ".id", isDirectory: false)
    }

    /// What `readOrCreate` did, logged by `StoreHomeRecorder`.
    public enum Event: String, Sendable, Equatable {
        /// The existing identifier was read.
        case kept
        /// There was no identifier file, so one was created.
        case created
        /// The identifier file couldn't be read or held no UUID, so it was replaced and the store's identity changed.
        case replacedUnreadable
        /// No identifier could be read or written.
        case unavailable
    }

    /// The store's identifier, or `nil` when there is none yet or it can't be read.
    public static func read(forStoreAt storeURL: URL) -> UUID? {
        guard let data = try? Data(contentsOf: url(forStoreAt: storeURL)),
            let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The store's identifier, created and written atomically if missing or unreadable, and what was done.
    public static func readOrCreate(forStoreAt storeURL: URL) -> (identifier: UUID?, event: Event) {
        if let existing = read(forStoreAt: storeURL) {
            return (existing, .kept)
        }
        let file = url(forStoreAt: storeURL)
        let replacing = FileManager.default.fileExists(atPath: file.path)
        let identifier = UUID()
        do {
            try Data(identifier.uuidString.utf8).write(to: file, options: .atomic)
        } catch {
            return (nil, .unavailable)
        }
        return (identifier, replacing ? .replacedUnreadable : .created)
    }
}

/// Tells whether a store file holds data: any account or transaction, as for backups (D179.3). Seeded default
/// categories alone don't count. `StoreLocation` asks it before choosing a location; tests inject their own.
public struct StoreContentsCheck: Sendable {
    public var hasData: @Sendable (URL) -> Bool

    public init(hasData: @escaping @Sendable (URL) -> Bool) {
        self.hasData = hasData
    }

    /// Where SwiftData is available, counts accounts and transactions in a scratch copy of the store, opened
    /// read-only with the current schema, so the store itself is never opened or changed (`StoreContentsProbe`). A
    /// store that exists but can't be opened counts as holding data, so it is never left behind. Elsewhere, as on
    /// Linux, it is `fileHasBytes`.
    public static let system = StoreContentsCheck { url in
        #if canImport(SwiftData)
            StoreContentsProbe.hasRecords(at: url)
        #else
            fileHasBytes.hasData(url)
        #endif
    }

    /// A store holds data exactly when its file exists and isn't empty. Test-only in practice: it is the `#else`
    /// branch of `system`, and Linux builds no app, so no shipping build decides with it. It is a stand-in for the
    /// SwiftData probe, not a definition of "holds data"; don't use it in app code.
    public static let fileHasBytes = StoreContentsCheck { url in
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
        return (size ?? 0) > 0
    }
}

/// What the app records once the store has opened: the location `StoreLocation` chose and where its marker and
/// the extensions' copy go.
public struct StoreHomeRecord: Sendable, Equatable {
    public var home: StoreHome
    /// `Application Support/<bundle id>/StoreHome.json`.
    public var markerURL: URL
    /// `<group container>/StoreHome.json` when the container was reachable at launch, otherwise `nil`.
    public var groupCopyURL: URL?

    public init(home: StoreHome, markerURL: URL, groupCopyURL: URL?) {
        self.home = home
        self.markerURL = markerURL
        self.groupCopyURL = groupCopyURL
    }
}

/// How writing one marker went.
public enum StoreHomeWrite: String, Sendable, Equatable {
    /// It already said the same thing, so it wasn't written.
    case unchanged
    case written
    /// Writing it failed. The launch goes on; the next launch tries again.
    case failed
    /// There is no group copy to write, because the container wasn't reachable.
    case skipped
}

/// The result of `StoreHomeRecorder.record`, logged as reasons only.
public struct StoreHomeRecordOutcome: Sendable, Equatable {
    public var marker: StoreHomeWrite
    public var groupCopy: StoreHomeWrite
    /// What happened to the store's identifier.
    public var storeID: StoreIdentity.Event

    public init(marker: StoreHomeWrite, groupCopy: StoreHomeWrite, storeID: StoreIdentity.Event = .kept) {
        self.marker = marker
        self.groupCopy = groupCopy
        self.storeID = storeID
    }
}

/// Writes the store-home marker after a successful open, only when it changes, and never fails the launch.
public enum StoreHomeRecorder {
    /// Records `record` with the app's file markers and the store's identifier beside `storeURL`, and logs the
    /// outcome. `LittleOrbitStore.makeContainer` calls this right after opening a writable store.
    @discardableResult
    public static func record(_ record: StoreHomeRecord, storeURL: URL) -> StoreHomeRecordOutcome {
        let identity = StoreIdentity.readOrCreate(forStoreAt: storeURL)
        var outcome = self.record(
            record.home,
            storeID: identity.identifier,
            marker: FileStoreHomeMarkerStore(url: record.markerURL),
            groupCopy: record.groupCopyURL.map(FileStoreHomeMarkerStore.init(url:)),
        )
        outcome.storeID = identity.event
        log(outcome)
        return outcome
    }

    /// Writes `home` with `storeID` to `marker`, and to `groupCopy` when there is one, each only when it differs
    /// from what is there. Failures are reported, never thrown.
    @discardableResult
    public static func record(
        _ home: StoreHome,
        storeID: UUID?,
        marker: any StoreHomeMarkerStore,
        groupCopy: (any StoreHomeMarkerStore)?,
    ) -> StoreHomeRecordOutcome {
        var recorded = home
        recorded.storeID = storeID
        let copyWrite = groupCopy.map { write(recorded, to: $0) } ?? .skipped
        return StoreHomeRecordOutcome(
            marker: write(recorded, to: marker),
            groupCopy: copyWrite,
            storeID: storeID == nil ? .unavailable : .kept,
        )
    }

    /// The log line for `outcome`: reasons only, no paths or user data.
    public static func summary(of outcome: StoreHomeRecordOutcome) -> String {
        var line = "Store home: marker \(outcome.marker.rawValue), group copy \(outcome.groupCopy.rawValue)"
        if outcome.storeID != .kept {
            line += ", store ID \(outcome.storeID.rawValue)"
        }
        return line
    }

    private static func write(_ home: StoreHome, to store: any StoreHomeMarkerStore) -> StoreHomeWrite {
        if case .recorded(home) = store.read() {
            return .unchanged
        }
        do {
            try store.write(home)
            return .written
        } catch {
            return .failed
        }
    }

    private static func log(_ outcome: StoreHomeRecordOutcome) {
        guard outcome != StoreHomeRecordOutcome(marker: .unchanged, groupCopy: .unchanged),
            outcome != StoreHomeRecordOutcome(marker: .unchanged, groupCopy: .skipped)
        else {
            return
        }
        StoreLocation.log(summary(of: outcome))
    }
}

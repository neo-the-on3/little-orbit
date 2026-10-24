import Foundation

/// Finds the container of an App Group. `system` asks `FileManager`; tests inject their own lookup.
public struct AppGroupContainerLookup: Sendable {
    public var containerURL: @Sendable (String) -> URL?

    public init(containerURL: @escaping @Sendable (String) -> URL?) {
        self.containerURL = containerURL
    }

    /// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`.
    ///
    /// On iOS it returns `nil` unless the app is signed with that App Group entitlement, so simulators, CI and
    /// unprovisioned builds use the fallback. On macOS it always returns a URL of the expected form
    /// (`~/Library/Group Containers/<id>/`), even when the group isn't valid for the app, and recent macOS
    /// versions may prompt when the ID isn't team-prefixed. That has no effect today, because the Info.plist key
    /// isn't set. Before the App Group is enabled, the store-move work must also check on macOS that the
    /// container is accessible before choosing it.
    public static let system = AppGroupContainerLookup { identifier in
        #if canImport(Darwin)
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
            nil
        #endif
    }

    /// No App Group container, as on Linux.
    public static let unavailable = AppGroupContainerLookup { _ in nil }
}

/// Where the on-device store lives.
///
/// 1. If Info.plist names an App Group (`LittleOrbitAppGroupIdentifier`) and the system returns that group's
///    container, the store is `<group container>/LittleOrbit.store`, shared with the app's extensions.
/// 2. Otherwise it is `Application Support/<bundle id>/LittleOrbit.store`.
///
/// SwiftData's default URL is `Application Support/default.store`, which an unsandboxed Mac app shares
/// with every other unsandboxed SwiftData app. Both locations avoid that, on iOS and macOS alike.
/// No App Group is configured yet: that needs an entitlement and a provisioning profile (D154).
public enum StoreLocation {
    public static let fileName = "LittleOrbit.store"
    /// The pending-seed marker's name suffix (D293). See `pendingSeedMarkerURL(forStore:)`.
    public static let pendingSeedMarkerSuffix = ".pending-seed"
    /// Folder name when there is no bundle identifier, such as in a command-line test run.
    public static let fallbackFolderName = "LittleOrbit"
    /// The optional Info.plist key that holds the App Group identifier.
    public static let appGroupInfoKey = "LittleOrbitAppGroupIdentifier"

    /// The App Group identifier in `infoDictionary`, or `nil` when it's missing, blank or not a string.
    public static func appGroupIdentifier(infoDictionary: [String: Any]?) -> String? {
        nonBlank(infoDictionary?[appGroupInfoKey] as? String)
    }

    /// The App Group identifier in the main bundle's Info.plist, if any.
    public static var bundleAppGroupIdentifier: String? {
        appGroupIdentifier(infoDictionary: Bundle.main.infoDictionary)
    }

    /// The store URL inside `applicationSupport`. Pure, so it is testable on Linux.
    public static func storeURL(applicationSupport: URL, bundleIdentifier: String?) -> URL {
        let folder = nonBlank(bundleIdentifier) ?? fallbackFolderName
        return
            applicationSupport
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// The store URL in the App Group container, or `nil` when there is no group ID or no container for it.
    public static func groupStoreURL(appGroupIdentifier: String?, lookup: AppGroupContainerLookup) -> URL? {
        guard let identifier = nonBlank(appGroupIdentifier), let container = lookup.containerURL(identifier) else {
            return nil
        }
        return container.appendingPathComponent(fileName, isDirectory: false)
    }

    /// The pending-seed marker for the store at `storeURL`: an empty file beside it, in the same folder, named
    /// `LittleOrbit.store.pending-seed` (D293). `LittleOrbitStore.makeRepository` writes it, atomically, just
    /// before the container creates a store file that didn't exist, and removes it once a seed save succeeds or a
    /// restore or import completes. A missing marker means seeded, so existing installs never seed. It holds no
    /// data, and backups never include it: they hold the ledger's records, not files from this folder.
    ///
    /// Note for #98: the App Group move must resolve the store's final URL first, then decide whether the store is
    /// new and carry this marker with it. If the store isn't empty, drop the marker instead. An existing install
    /// must never seed an empty group store.
    public static func pendingSeedMarkerURL(forStore storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + pendingSeedMarkerSuffix, isDirectory: false)
    }

    /// The store URL with its folder created if missing. SwiftData creates the store file itself.
    public static func prepareStoreURL(
        applicationSupport: URL? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appGroupIdentifier: String? = StoreLocation.bundleAppGroupIdentifier,
        groupContainer: AppGroupContainerLookup = .system,
        fileManager: FileManager = .default,
    ) throws -> URL {
        let url: URL
        if let groupURL = groupStoreURL(appGroupIdentifier: appGroupIdentifier, lookup: groupContainer) {
            url = groupURL
        } else {
            let base =
                try applicationSupport
                ?? fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true,
                )
            url = storeURL(applicationSupport: base, bundleIdentifier: bundleIdentifier)
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    private static func nonBlank(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension StoreConfiguration {
    /// The app's local store, with sync off: in the App Group container when one is configured and available,
    /// otherwise in the app's own Application Support folder.
    public static func appLocal(
        applicationSupport: URL? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appGroupIdentifier: String? = StoreLocation.bundleAppGroupIdentifier,
        groupContainer: AppGroupContainerLookup = .system,
        fileManager: FileManager = .default,
    ) throws -> StoreConfiguration {
        let url = try StoreLocation.prepareStoreURL(
            applicationSupport: applicationSupport,
            bundleIdentifier: bundleIdentifier,
            appGroupIdentifier: appGroupIdentifier,
            groupContainer: groupContainer,
            fileManager: fileManager,
        )
        return StoreConfiguration(fileURL: url)
    }
}

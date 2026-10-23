import Foundation

#if canImport(os)
    import os
#endif
#if os(macOS)
    import Security
#endif

/// Finds the container of an App Group. `system` asks `FileManager`; tests inject their own lookup.
public struct AppGroupContainerLookup: Sendable {
    public var containerURL: @Sendable (String) -> URL?

    public init(containerURL: @escaping @Sendable (String) -> URL?) {
        self.containerURL = containerURL
    }

    /// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`.
    ///
    /// On iOS it returns `nil` unless the app is signed with that App Group entitlement, so
    /// `AppGroupEntitlementCheck.system` treats `nil` there as not entitled: simulator builds with signing off,
    /// CI and unprovisioned builds use the fallback. On macOS it always returns a URL of the expected form
    /// (`~/Library/Group Containers/<id>/`), even when the app isn't entitled to the group, so the entitlement
    /// is read from the app's signature there.
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

/// Tells whether this app is signed with an App Group entitlement. `system` reads the app's own signature;
/// tests inject their own answer.
public struct AppGroupEntitlementCheck: Sendable {
    public var isEntitled: @Sendable (String) -> Bool

    public init(isEntitled: @escaping @Sendable (String) -> Bool) {
        self.isEntitled = isEntitled
    }

    /// The `com.apple.security.application-groups` entitlement of the running app.
    ///
    /// macOS reads it from the app's code signature, because the container lookup there succeeds for any ID.
    /// iOS has no public API for this, but its container lookup returns `nil` exactly when the app isn't
    /// entitled, so there a missing container means not entitled (`containerPresence(.system)`), and the build
    /// falls back with `notEntitled`. Elsewhere there are no App Groups.
    public static let system = AppGroupEntitlementCheck { identifier in
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil) else {
                return false
            }
            let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil,
            )
            return (value as? [String])?.contains(identifier) ?? false
        #elseif canImport(Darwin)
            containerPresence(.system).isEntitled(identifier)
        #else
            false
        #endif
    }

    /// Entitled exactly when `lookup` returns a container for the group, which is how iOS reports the
    /// entitlement.
    public static func containerPresence(_ lookup: AppGroupContainerLookup) -> AppGroupEntitlementCheck {
        AppGroupEntitlementCheck { lookup.containerURL($0) != nil }
    }

    /// Entitled to every group. For tests.
    public static let granted = AppGroupEntitlementCheck { _ in true }

    /// Entitled to no group, as in an unsigned build.
    public static let denied = AppGroupEntitlementCheck { _ in false }
}

/// Why the store is in Application Support instead of the App Group container.
public enum StoreFallbackReason: String, Sendable, Equatable {
    /// Info.plist names no App Group. A property of the build.
    case noAppGroupConfigured
    /// The app isn't signed with the App Group entitlement, as in simulator builds with signing off. A property of
    /// the build.
    case notEntitled
    /// The app is entitled, but the group container is missing or can't be written, and no group store has been
    /// recorded, so there is nothing in the group to leave behind (Kiran's ask on #98).
    case containerUnavailable
    /// The app is entitled and the container is fine, but the store is already in the app folder (its marker says
    /// so, or it holds data and no group store was recorded). It stays there until #102 moves it.
    case awaitingMigration
}

/// Why a build that is entitled to its App Group can't use the group container.
public enum AppGroupContainerFailure: String, Sendable, Equatable {
    /// The system returned no container for the group.
    case noContainer
    /// The group container's folder couldn't be created.
    case containerNotWritable
}

/// Why a build can't open a store that its marker says is in an App Group (`StoreError.storeIsInAppGroup`).
public enum StoreHomeConflict: String, Sendable, Equatable {
    /// This build names no App Group.
    case noAppGroupConfigured
    /// This build isn't entitled to the group.
    case notEntitled
    /// This build names a different group, for example after a builder override.
    case groupIdentifierChanged
}

/// Why a launch rewrites the store-home marker from what's on disk instead of following it. Each is logged with the
/// chosen location (`marker repaired: <reason>`), so it can be told apart from a normal launch.
public enum StoreHomeRepair: String, Sendable, Equatable {
    /// The marker said `appFolder`, but the app-folder store is empty and the group store holds data, so the group
    /// store is used and the marker becomes `group`.
    case appFolderEmptyGroupHasData
    /// No marker, and the group store holds data: the group store, and marker=`group` is written.
    case noMarkerGroupHasData
    /// No marker, and the app-folder store holds data: the app folder, and marker=`appFolder` is written.
    case noMarkerAppFolderHasData
    /// The marker couldn't be read. The location was decided by disk (or by the build when it isn't entitled) and
    /// the marker is rewritten.
    case unreadableMarker
}

/// Which of the two store locations was chosen.
public enum StoreLocationKind: Sendable, Equatable {
    /// `<group container>/LittleOrbit.store`, shared with the app's extensions.
    case appGroup(identifier: String)
    /// `Application Support/<bundle id>/LittleOrbit.store`, private to the app.
    case applicationSupport(StoreFallbackReason)
}

/// The store URL and the location it is in. Its folder exists; SwiftData creates the store file itself.
public struct ResolvedStoreLocation: Sendable, Equatable {
    public var url: URL
    public var kind: StoreLocationKind
    /// What to record once the store has opened (`StoreHomeRecorder`).
    public var homeRecord: StoreHomeRecord?
    /// Why the marker is being rewritten from what's on disk, when it is. Logged with the location.
    public var repair: StoreHomeRepair?

    public init(
        url: URL,
        kind: StoreLocationKind,
        homeRecord: StoreHomeRecord? = nil,
        repair: StoreHomeRepair? = nil,
    ) {
        self.url = url
        self.kind = kind
        self.homeRecord = homeRecord
        self.repair = repair
    }
}

/// Where the on-device store lives. This is the one place that decides it.
///
/// The store is either `<group container>/LittleOrbit.store`, shared with the app's extensions, or
/// `Application Support/<bundle id>/LittleOrbit.store`. The group is the one Info.plist names
/// (`LittleOrbitAppGroupIdentifier`, from the `LITTLEORBIT_APP_GROUP_IDENTIFIER` build setting).
///
/// After each successful open the app records where its store is, in a store-home marker
/// (`Application Support/<bundle id>/StoreHome.json`, see `StoreHomeRecorder`). The choice follows that marker and
/// what is on disk, so a store only moves through #102's one-time migration, never because of one bad launch:
/// 1. Entitled and the container is usable: the group store, unless the store is already in the app folder (the
///    marker says so, or the app-folder store holds data and no group store was recorded). Then it stays in the app
///    folder (`awaitingMigration`) until #102 moves it. Both holding data is `StoreError.storesInBothLocations`,
///    never a merge.
/// 2. Entitled but the container is missing or can't be written: the app folder (`containerUnavailable`) when no
///    group store was recorded. When one was, it throws `StoreError.appGroupContainerUnavailable` and opens no
///    empty store.
/// 3. No group configured or not entitled: the app folder, as before. When the marker says the store is in a
///    group, or in a different group than the configured one, it throws `StoreError.storeIsInAppGroup` instead.
///
/// SwiftData's default URL is `Application Support/default.store`, which an unsandboxed Mac app shares
/// with every other unsandboxed SwiftData app. Both locations avoid that, on iOS and macOS alike.
public enum StoreLocation {
    public static let fileName = "LittleOrbit.store"
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

    /// Chooses the store location and creates its folder if missing. `marker` defaults to the app's
    /// `StoreHome.json`. Throws `StoreError.appGroupContainerUnavailable`, `.storeIsInAppGroup` or
    /// `.storesInBothLocations` when no location can be chosen without hiding or splitting data.
    public static func resolve(
        applicationSupport: URL? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appGroupIdentifier: String? = StoreLocation.bundleAppGroupIdentifier,
        groupContainer: AppGroupContainerLookup = .system,
        entitlement: AppGroupEntitlementCheck = .system,
        marker: (any StoreHomeMarkerStore)? = nil,
        contents: StoreContentsCheck = .system,
        fileManager: FileManager = .default,
    ) throws -> ResolvedStoreLocation {
        let base =
            try applicationSupport
            ?? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true,
            )
        let appFolderURL = storeURL(applicationSupport: base, bundleIdentifier: bundleIdentifier)
        let markerFile = FileStoreHomeMarkerStore.appFolder(
            applicationSupport: base,
            bundleIdentifier: bundleIdentifier,
        )
        let decision = try decide(
            group: nonBlank(appGroupIdentifier),
            marker: (marker ?? markerFile).read(),
            appFolderURL: appFolderURL,
            groupContainer: groupContainer,
            entitlement: entitlement,
            contents: contents,
            fileManager: fileManager,
        )
        switch decision {
        case .group(let identifier, let url, let repair):
            let record = StoreHomeRecord(
                home: .group(identifier),
                markerURL: markerFile.url,
                groupCopyURL: url.deletingLastPathComponent().appendingPathComponent(FileStoreHomeMarkerStore.fileName),
            )
            return ResolvedStoreLocation(
                url: url,
                kind: .appGroup(identifier: identifier),
                homeRecord: record,
                repair: repair,
            )
        case .appFolder(let reason, let groupContainerURL, let repair):
            try fileManager.createDirectory(
                at: appFolderURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            let record = StoreHomeRecord(
                home: .appFolder(),
                markerURL: markerFile.url,
                groupCopyURL: groupContainerURL?.appendingPathComponent(FileStoreHomeMarkerStore.fileName),
            )
            return ResolvedStoreLocation(
                url: appFolderURL,
                kind: .applicationSupport(reason),
                homeRecord: record,
                repair: repair,
            )
        }
    }

    /// The store in the App Group container only, for an extension that reads the app's store. It follows the same
    /// rule read-only and never creates a file or folder. An extension has no use for its own Application Support
    /// folder, so there is no fallback: it throws `StoreError.sharedStoreUnavailable` without the group,
    /// `StoreError.appGroupContainerUnavailable` without the container, and `StoreError.sharedStoreNotInGroup`
    /// when the app's store-home copy in the group is missing or doesn't name this group's store.
    public static func sharedStoreURL(
        appGroupIdentifier: String? = StoreLocation.bundleAppGroupIdentifier,
        groupContainer: AppGroupContainerLookup = .system,
        entitlement: AppGroupEntitlementCheck = .system,
        groupCopy: (any StoreHomeMarkerStore)? = nil,
    ) throws -> URL {
        guard let identifier = nonBlank(appGroupIdentifier) else {
            throw StoreError.sharedStoreUnavailable(.noAppGroupConfigured)
        }
        guard entitlement.isEntitled(identifier) else {
            throw StoreError.sharedStoreUnavailable(.notEntitled)
        }
        guard let container = groupContainer.containerURL(identifier) else {
            throw StoreError.appGroupContainerUnavailable(.noContainer)
        }
        let copy = groupCopy ?? FileStoreHomeMarkerStore.groupCopy(container: container)
        guard case .recorded(let home) = copy.read(), home.isSameLocation(as: .group(identifier)) else {
            throw StoreError.sharedStoreNotInGroup
        }
        return container.appendingPathComponent(fileName, isDirectory: false)
    }

    /// The store URL with its folder created if missing, and the chosen location logged.
    public static func prepareStoreURL(
        applicationSupport: URL? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appGroupIdentifier: String? = StoreLocation.bundleAppGroupIdentifier,
        groupContainer: AppGroupContainerLookup = .system,
        entitlement: AppGroupEntitlementCheck = .system,
        marker: (any StoreHomeMarkerStore)? = nil,
        contents: StoreContentsCheck = .system,
        fileManager: FileManager = .default,
    ) throws -> URL {
        try prepare(
            applicationSupport: applicationSupport,
            bundleIdentifier: bundleIdentifier,
            appGroupIdentifier: appGroupIdentifier,
            groupContainer: groupContainer,
            entitlement: entitlement,
            marker: marker,
            contents: contents,
            fileManager: fileManager,
        )
        .url
    }

    /// `resolve`, with the chosen location logged.
    static func prepare(
        applicationSupport: URL?,
        bundleIdentifier: String?,
        appGroupIdentifier: String?,
        groupContainer: AppGroupContainerLookup,
        entitlement: AppGroupEntitlementCheck,
        marker: (any StoreHomeMarkerStore)?,
        contents: StoreContentsCheck,
        fileManager: FileManager,
    ) throws -> ResolvedStoreLocation {
        let resolved = try resolve(
            applicationSupport: applicationSupport,
            bundleIdentifier: bundleIdentifier,
            appGroupIdentifier: appGroupIdentifier,
            groupContainer: groupContainer,
            entitlement: entitlement,
            marker: marker,
            contents: contents,
            fileManager: fileManager,
        )
        log(summary(of: resolved))
        return resolved
    }

    /// A one-line description of the chosen location, without the path. This is what the app logs.
    public static func summary(of kind: StoreLocationKind) -> String {
        switch kind {
        case .appGroup(let identifier):
            "Store location: App Group container \(identifier)"
        case .applicationSupport(let reason):
            "Store location: Application Support (fallback: \(reason.rawValue))"
        }
    }

    /// The launch log line: the location, plus the marker repair when there is one, so a repaired marker can be
    /// told apart from a normal launch. Reasons only, no path.
    public static func summary(of resolved: ResolvedStoreLocation) -> String {
        guard let repair = resolved.repair else {
            return summary(of: resolved.kind)
        }
        return summary(of: resolved.kind) + " (marker repaired: \(repair.rawValue))"
    }

    /// Logs `line`, which carries reasons only, never a path or user data.
    static func log(_ line: String) {
        #if canImport(os)
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? fallbackFolderName, category: "Store")
            logger.notice("\(line, privacy: .public)")
        #endif
    }

    static func nonBlank(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension StoreConfiguration {
    /// The app's local store, with sync off, where `StoreLocation.resolve` puts it. Its store-home record is
    /// written by `LittleOrbitStore.makeContainer` once the store opens. Throws what `resolve` throws.
    public static func appLocal(
        applicationSupport: URL? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appGroupIdentifier: String? = StoreLocation.bundleAppGroupIdentifier,
        groupContainer: AppGroupContainerLookup = .system,
        entitlement: AppGroupEntitlementCheck = .system,
        marker: (any StoreHomeMarkerStore)? = nil,
        contents: StoreContentsCheck = .system,
        fileManager: FileManager = .default,
    ) throws -> StoreConfiguration {
        let resolved = try StoreLocation.prepare(
            applicationSupport: applicationSupport,
            bundleIdentifier: bundleIdentifier,
            appGroupIdentifier: appGroupIdentifier,
            groupContainer: groupContainer,
            entitlement: entitlement,
            marker: marker,
            contents: contents,
            fileManager: fileManager,
        )
        return StoreConfiguration(fileURL: resolved.url, homeRecord: resolved.homeRecord)
    }

    /// The app's store in the App Group container, opened read-only, for an extension such as a widget. Throws
    /// what `StoreLocation.sharedStoreURL` throws; a missing or stale store-home copy means no data. Opening it
    /// before the app has created the store throws `StoreError.readOnlyStoreMissing` and creates no file.
    public static func sharedReadOnly(
        appGroupIdentifier: String? = StoreLocation.bundleAppGroupIdentifier,
        groupContainer: AppGroupContainerLookup = .system,
        entitlement: AppGroupEntitlementCheck = .system,
        groupCopy: (any StoreHomeMarkerStore)? = nil,
    ) throws -> StoreConfiguration {
        let url = try StoreLocation.sharedStoreURL(
            appGroupIdentifier: appGroupIdentifier,
            groupContainer: groupContainer,
            entitlement: entitlement,
            groupCopy: groupCopy,
        )
        return StoreConfiguration(fileURL: url, readOnly: true)
    }
}

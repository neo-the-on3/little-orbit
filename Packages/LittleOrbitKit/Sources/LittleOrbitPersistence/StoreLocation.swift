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

/// Why the store is in Application Support instead of the App Group container. Both reasons are properties of
/// the build, so a build that falls back always falls back.
public enum StoreFallbackReason: String, Sendable, Equatable {
    /// Info.plist names no App Group.
    case noAppGroupConfigured
    /// The app isn't signed with the App Group entitlement, as in simulator builds with signing off.
    case notEntitled
}

/// Why a build that is entitled to its App Group can't use the group container. These are runtime failures,
/// so the store throws `StoreError.appGroupContainerUnavailable` instead of opening a second, empty store in
/// Application Support that the next good launch would leave behind.
public enum AppGroupContainerFailure: String, Sendable, Equatable {
    /// The system returned no container for the group.
    case noContainer
    /// The group container's folder couldn't be created.
    case containerNotWritable
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

    public init(url: URL, kind: StoreLocationKind) {
        self.url = url
        self.kind = kind
    }
}

/// Where the on-device store lives. This is the one place that decides it.
///
/// 1. If Info.plist names an App Group (`LittleOrbitAppGroupIdentifier`, set from the
///    `LITTLEORBIT_APP_GROUP_IDENTIFIER` build setting), the app is entitled to it and its container folder can
///    be created, the store is `<group container>/LittleOrbit.store`, shared with the app's extensions.
/// 2. If no App Group is configured or the app isn't entitled to it, it is
///    `Application Support/<bundle id>/LittleOrbit.store`.
/// 3. If the app is entitled but the container is missing or its folder can't be created, opening the store
///    throws `StoreError.appGroupContainerUnavailable`. It never falls back then.
///
/// The choice depends only on the build and its signature, so a build never alternates between the two and
/// starts empty on a later launch. Nothing is copied between them: per D34.2 a dev store from PR #51 is left
/// where it is and never merged.
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

    /// Chooses the store location and creates its folder if missing. Throws
    /// `StoreError.appGroupContainerUnavailable` when the app is entitled to its group but can't use the
    /// container.
    public static func resolve(
        applicationSupport: URL? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appGroupIdentifier: String? = StoreLocation.bundleAppGroupIdentifier,
        groupContainer: AppGroupContainerLookup = .system,
        entitlement: AppGroupEntitlementCheck = .system,
        fileManager: FileManager = .default,
    ) throws -> ResolvedStoreLocation {
        let reason: StoreFallbackReason
        switch try appGroup(
            identifier: appGroupIdentifier,
            groupContainer: groupContainer,
            entitlement: entitlement,
            fileManager: fileManager,
        ) {
        case .available(let resolved):
            return resolved
        case .fallback(let fallback):
            reason = fallback
        }
        let base =
            try applicationSupport
            ?? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true,
            )
        let url = storeURL(applicationSupport: base, bundleIdentifier: bundleIdentifier)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return ResolvedStoreLocation(url: url, kind: .applicationSupport(reason))
    }

    /// The store URL with its folder created if missing, and the chosen location logged.
    public static func prepareStoreURL(
        applicationSupport: URL? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appGroupIdentifier: String? = StoreLocation.bundleAppGroupIdentifier,
        groupContainer: AppGroupContainerLookup = .system,
        entitlement: AppGroupEntitlementCheck = .system,
        fileManager: FileManager = .default,
    ) throws -> URL {
        let resolved = try resolve(
            applicationSupport: applicationSupport,
            bundleIdentifier: bundleIdentifier,
            appGroupIdentifier: appGroupIdentifier,
            groupContainer: groupContainer,
            entitlement: entitlement,
            fileManager: fileManager,
        )
        log(resolved)
        return resolved.url
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

    private enum AppGroupOutcome {
        case available(ResolvedStoreLocation)
        case fallback(StoreFallbackReason)
    }

    /// The group store, or the build-dependent reason not to use it. Throws once the app is entitled to the
    /// group, because falling back then would split the data between two stores.
    private static func appGroup(
        identifier: String?,
        groupContainer: AppGroupContainerLookup,
        entitlement: AppGroupEntitlementCheck,
        fileManager: FileManager,
    ) throws -> AppGroupOutcome {
        guard let identifier = nonBlank(identifier) else {
            return .fallback(.noAppGroupConfigured)
        }
        guard entitlement.isEntitled(identifier) else {
            return .fallback(.notEntitled)
        }
        guard let url = groupStoreURL(appGroupIdentifier: identifier, lookup: groupContainer) else {
            throw StoreError.appGroupContainerUnavailable(.noContainer)
        }
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw StoreError.appGroupContainerUnavailable(.containerNotWritable)
        }
        return .available(ResolvedStoreLocation(url: url, kind: .appGroup(identifier: identifier)))
    }

    private static func log(_ resolved: ResolvedStoreLocation) {
        #if canImport(os)
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? fallbackFolderName, category: "Store")
            logger.notice("\(summary(of: resolved.kind), privacy: .public) at \(resolved.url.path, privacy: .private)")
        #endif
    }

    private static func nonBlank(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension StoreConfiguration {
    /// The app's local store, with sync off: in the App Group container when one is configured and the app is
    /// entitled to it, otherwise in the app's own Application Support folder. Throws
    /// `StoreError.appGroupContainerUnavailable` when the app is entitled but can't use the container.
    public static func appLocal(
        applicationSupport: URL? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appGroupIdentifier: String? = StoreLocation.bundleAppGroupIdentifier,
        groupContainer: AppGroupContainerLookup = .system,
        entitlement: AppGroupEntitlementCheck = .system,
        fileManager: FileManager = .default,
    ) throws -> StoreConfiguration {
        let url = try StoreLocation.prepareStoreURL(
            applicationSupport: applicationSupport,
            bundleIdentifier: bundleIdentifier,
            appGroupIdentifier: appGroupIdentifier,
            groupContainer: groupContainer,
            entitlement: entitlement,
            fileManager: fileManager,
        )
        return StoreConfiguration(fileURL: url)
    }
}

import Foundation

/// The store-home rule (#52, agreed on #98). Rows refer to the decision table in docs/persistence-migration.md.
extension StoreLocation {
    enum Decision: Equatable {
        case group(identifier: String, url: URL, repair: StoreHomeRepair?)
        /// The app folder, with the group container's URL when it was reachable, for the extensions' copy.
        case appFolder(StoreFallbackReason, groupContainer: URL?, repair: StoreHomeRepair?)
    }

    private enum Container {
        case usable(URL)
        case unavailable(AppGroupContainerFailure)
    }

    static func decide(
        group: String?,
        marker: StoreHomeMarkerState,
        appFolderURL: URL,
        groupContainer: AppGroupContainerLookup,
        entitlement: AppGroupEntitlementCheck,
        contents: StoreContentsCheck,
        fileManager: FileManager,
    ) throws -> Decision {
        let recorded: StoreHome? = if case .recorded(let home) = marker { home } else { nil }
        try checkRecordedGroup(recorded, group: group, entitlement: entitlement)
        // Row 7: no group or not entitled. An unreadable marker can't be told apart from no marker here, so the app
        // folder is used and the marker is then rewritten as `appFolder`; that is logged as `unreadableMarker`.
        let unreadable: StoreHomeRepair? = marker == .unreadable ? .unreadableMarker : nil
        guard let group else {
            return .appFolder(.noAppGroupConfigured, groupContainer: nil, repair: unreadable)
        }
        guard entitlement.isEntitled(group) else {
            return .appFolder(.notEntitled, groupContainer: nil, repair: unreadable)
        }
        switch container(for: group, lookup: groupContainer, fileManager: fileManager) {
        case .unavailable(let failure):
            // Row 4: a recorded group store (or a marker that can't be read) is never replaced by an empty one.
            if marker == .unreadable || recorded?.kind == .group {
                throw StoreError.appGroupContainerUnavailable(failure)
            }
            // Row 3: nothing was recorded in the group, so the app folder is safe (Kiran's ask).
            return .appFolder(.containerUnavailable, groupContainer: nil, repair: nil)
        case .usable(let container):
            return try decideWithContainer(
                container,
                group: group,
                marker: marker,
                appFolderURL: appFolderURL,
                contents: contents,
                fileManager: fileManager,
            )
        }
    }

    /// Rows 5 and 6: the store is recorded in a group this build can't use. Never a silent switch.
    private static func checkRecordedGroup(
        _ recorded: StoreHome?,
        group: String?,
        entitlement: AppGroupEntitlementCheck,
    ) throws {
        guard let recorded, recorded.kind == .group else {
            return
        }
        guard let group else {
            throw StoreError.storeIsInAppGroup(.noAppGroupConfigured)
        }
        guard recorded.groupIdentifier == group else {
            throw StoreError.storeIsInAppGroup(.groupIdentifierChanged)
        }
        guard entitlement.isEntitled(group) else {
            throw StoreError.storeIsInAppGroup(.notEntitled)
        }
    }

    /// Rows 1 and 2: entitled and the container is usable. Probing a store costs a copy and a count, so it only
    /// happens when the answer can change the location: a store file that doesn't exist holds no data, and the
    /// group store is probed first because without group data neither C1 nor both-locations is possible.
    private static func decideWithContainer(
        _ container: URL,
        group: String,
        marker: StoreHomeMarkerState,
        appFolderURL: URL,
        contents: StoreContentsCheck,
        fileManager: FileManager,
    ) throws -> Decision {
        let groupURL = container.appendingPathComponent(fileName, isDirectory: false)
        // Row 1 with marker=group: the group store, whatever else is on disk. No probe.
        if case .recorded(let home) = marker, home.kind == .group {
            return .group(identifier: group, url: groupURL, repair: nil)
        }
        let groupHasData = fileManager.fileExists(atPath: groupURL.path) && contents.hasData(groupURL)
        let appFolderHasData = {
            fileManager.fileExists(atPath: appFolderURL.path) && contents.hasData(appFolderURL)
        }
        // Row 2 with marker=appFolder: it stays in the app folder unless the group store holds data. With no group
        // store file (the steady state before #102, or after a row 3 fallback) nothing is probed.
        if isAppFolderMarker(marker) {
            guard groupHasData else {
                return .appFolder(.awaitingMigration, groupContainer: container, repair: nil)
            }
            if appFolderHasData() {
                throw StoreError.storesInBothLocations
            }
            // The app folder is empty and the group store holds data (C1).
            return .group(identifier: group, url: groupURL, repair: .appFolderEmptyGroupHasData)
        }
        // No marker, or an unreadable one: decide by which store holds data.
        if appFolderHasData() {
            if groupHasData {
                throw StoreError.storesInBothLocations
            }
            let repair: StoreHomeRepair = marker == .unreadable ? .unreadableMarker : .noMarkerAppFolderHasData
            return .appFolder(.awaitingMigration, groupContainer: container, repair: repair)
        }
        let repair: StoreHomeRepair? =
            if marker == .unreadable { .unreadableMarker } else { groupHasData ? .noMarkerGroupHasData : nil }
        return .group(identifier: group, url: groupURL, repair: repair)
    }

    private static func isAppFolderMarker(_ marker: StoreHomeMarkerState) -> Bool {
        if case .recorded(let home) = marker { home.kind == .appFolder } else { false }
    }

    private static func container(
        for group: String,
        lookup: AppGroupContainerLookup,
        fileManager: FileManager,
    ) -> Container {
        guard let container = lookup.containerURL(group) else {
            return .unavailable(.noContainer)
        }
        do {
            try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
        } catch {
            return .unavailable(.containerNotWritable)
        }
        return .usable(container)
    }
}

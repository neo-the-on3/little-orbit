import Foundation
import Testing

@testable import LittleOrbitPersistence

/// #52, rule agreed on #98: the store-home marker decides where the store is, together with which store holds
/// data, so a store only moves through #102's migration and never because of one bad launch.
@Suite("Store home marker (#52)")
struct StoreHomeRuleTests {
    static let group = "group.test.store"
    static let otherGroup = "group.test.other"
    static let bundle = "test.store.app"

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("store-home-\(UUID().uuidString)", isDirectory: true)

    var support: URL { root.appendingPathComponent("support", isDirectory: true) }
    var container: URL { root.appendingPathComponent("group", isDirectory: true) }
    var appFolderStore: URL {
        StoreLocation.storeURL(applicationSupport: support, bundleIdentifier: Self.bundle).standardizedFileURL
    }
    var groupStore: URL { container.appendingPathComponent("LittleOrbit.store").standardizedFileURL }
    var marker: FileStoreHomeMarkerStore {
        .appFolder(applicationSupport: support, bundleIdentifier: Self.bundle)
    }
    var groupCopy: FileStoreHomeMarkerStore { .groupCopy(container: container) }

    enum Container {
        case available
        case missing
        case notWritable
    }

    func lookup(_ state: Container) throws -> AppGroupContainerLookup {
        switch state {
        case .available:
            let container = container
            return AppGroupContainerLookup { $0 == Self.group ? container : nil }
        case .missing:
            return .unavailable
        case .notWritable:
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let blocker = root.appendingPathComponent("not-a-folder")
            try Data("x".utf8).write(to: blocker)
            return AppGroupContainerLookup { _ in blocker.appendingPathComponent("group", isDirectory: true) }
        }
    }

    func resolve(
        _ state: Container = .available,
        group: String? = Self.group,
        entitlement: AppGroupEntitlementCheck = .granted,
        contents: StoreContentsCheck = .fileHasBytes,
    ) throws -> ResolvedStoreLocation {
        try StoreLocation.resolve(
            applicationSupport: support,
            bundleIdentifier: Self.bundle,
            appGroupIdentifier: group,
            groupContainer: lookup(state),
            entitlement: entitlement,
            contents: contents,
        )
    }

    /// One launch: choose the location, open it (optionally entering data), and record the store home as
    /// `LittleOrbitStore.makeContainer` does after a successful open.
    @discardableResult
    func launch(
        _ state: Container = .available,
        group: String? = Self.group,
        entitlement: AppGroupEntitlementCheck = .granted,
        enteringData: Bool = false,
    ) throws -> ResolvedStoreLocation {
        let resolved = try resolve(state, group: group, entitlement: entitlement)
        if enteringData {
            try putData(at: resolved.url)
        }
        let record = try #require(resolved.homeRecord)
        StoreHomeRecorder.record(record, storeURL: resolved.url)
        return resolved
    }

    func putData(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("records".utf8).write(to: url)
    }

    func recordedHome(_ store: FileStoreHomeMarkerStore) -> StoreHome? {
        if case .recorded(let home) = store.read() { home } else { nil }
    }

    func isAppFolder(_ resolved: ResolvedStoreLocation, _ reason: StoreFallbackReason) -> Bool {
        resolved.kind == .applicationSupport(reason) && resolved.url.standardizedFileURL == appFolderStore
    }

    func isGroup(_ resolved: ResolvedStoreLocation) -> Bool {
        resolved.kind == .appGroup(identifier: Self.group) && resolved.url.standardizedFileURL == groupStore
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Row 1: entitled, container OK, marker none or group

    @Test("Row 1: no marker and no data anywhere, so the group store, and marker=group is written with a store ID")
    func rowOneFreshInstall() throws {
        defer { cleanUp() }
        let resolved = try launch()
        #expect(isGroup(resolved))
        let home = try #require(recordedHome(marker))
        #expect(home.kind == .group)
        #expect(home.groupIdentifier == Self.group)
        #expect(home.storeID != nil)
        #expect(home.storeID == StoreIdentity.read(forStoreAt: resolved.url))
        #expect(recordedHome(groupCopy) == home, "Extensions get the same record in the group")
        #expect(resolved.repair == nil, "A fresh install isn't a repair")
        #expect(StoreLocation.summary(of: resolved) == "Store location: App Group container group.test.store")
    }

    @Test("Row 1: no marker, but the app folder holds data, so it stays in the app folder")
    func rowOneAppFolderHasData() throws {
        defer { cleanUp() }
        try putData(at: appFolderStore)
        let resolved = try launch()
        #expect(isAppFolder(resolved, .awaitingMigration))
        #expect(resolved.repair == .noMarkerAppFolderHasData)
        #expect(recordedHome(marker)?.kind == .appFolder)
    }

    @Test("Row 1: marker=group keeps the group store even when the app folder holds data")
    func rowOneGroupMarkerWins() throws {
        defer { cleanUp() }
        try marker.write(.group(Self.group))
        try putData(at: appFolderStore)
        let resolved = try resolve()
        #expect(isGroup(resolved))
        #expect(resolved.repair == nil, "Following the marker isn't a repair")
    }

    @Test("Marker repair: no marker but a group store with data, so the group store and marker=group again")
    func markerRepairFromDisk() throws {
        defer { cleanUp() }
        try putData(at: groupStore)
        let resolved = try launch()
        #expect(isGroup(resolved))
        #expect(resolved.repair == .noMarkerGroupHasData)
        #expect(
            StoreLocation.summary(of: resolved)
                == "Store location: App Group container group.test.store (marker repaired: noMarkerGroupHasData)"
        )
        #expect(recordedHome(marker)?.isSameLocation(as: .group(Self.group)) == true)
    }

    @Test("Marker repair: an unreadable marker is decided by disk and rewritten")
    func markerRepairFromUnreadable() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(
            at: marker.url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("not json".utf8).write(to: marker.url)
        #expect(marker.read() == .unreadable)
        let resolved = try launch()
        #expect(isGroup(resolved))
        #expect(resolved.repair == .unreadableMarker)
        #expect(recordedHome(marker)?.kind == .group)
    }

    @Test("Marker repair: an unreadable marker with app-folder data stays in the app folder, logged as a repair")
    func markerRepairFromUnreadableWithAppFolderData() throws {
        defer { cleanUp() }
        try putData(at: appFolderStore)
        try Data("not json".utf8).write(to: marker.url)
        let resolved = try launch()
        #expect(isAppFolder(resolved, .awaitingMigration))
        #expect(resolved.repair == .unreadableMarker)
        #expect(recordedHome(marker)?.kind == .appFolder)
    }

    @Test("Marker repair: a build without the entitlement rewrites an unreadable marker as appFolder, logged")
    func markerRepairFromUnreadableNotEntitled() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(
            at: marker.url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("not json".utf8).write(to: marker.url)
        let resolved = try launch(entitlement: .denied)
        #expect(isAppFolder(resolved, .notEntitled))
        #expect(resolved.repair == .unreadableMarker)
        #expect(StoreLocation.summary(of: resolved).hasSuffix("(marker repaired: unreadableMarker)"))
        #expect(recordedHome(marker)?.kind == .appFolder)
    }

    // MARK: - Row 2: entitled, container OK, store already in the app folder

    @Test("Row 2: marker=appFolder stays in the app folder until #102 migrates, and the group copy says so")
    func rowTwoAppFolderMarker() throws {
        defer { cleanUp() }
        try marker.write(.appFolder())
        let resolved = try launch()
        #expect(isAppFolder(resolved, .awaitingMigration))
        #expect(resolved.repair == nil)
        #expect(recordedHome(groupCopy)?.kind == .appFolder)
        #expect(!FileManager.default.fileExists(atPath: groupStore.path), "No group store is created")
    }

    @Test("Row 2: both stores hold data, so the both-non-empty error, never a merge")
    func rowTwoBothHoldData() throws {
        defer { cleanUp() }
        try putData(at: appFolderStore)
        try putData(at: groupStore)
        #expect(throws: StoreError.storesInBothLocations) { try resolve() }
        try marker.write(.appFolder())
        #expect(throws: StoreError.storesInBothLocations) { try resolve() }
        #expect(try Data(contentsOf: appFolderStore) == Data("records".utf8))
        #expect(try Data(contentsOf: groupStore) == Data("records".utf8))
    }

    @Test("Row 2: marker=appFolder but only the group store holds data, so the group store (nothing to split)")
    func rowTwoEmptyAppFolderWithGroupData() throws {
        defer { cleanUp() }
        try marker.write(.appFolder())
        try putData(at: groupStore)
        let resolved = try launch()
        #expect(isGroup(resolved))
        #expect(resolved.repair == .appFolderEmptyGroupHasData, "B1: its own log reason")
        #expect(
            StoreLocation.summary(of: resolved)
                == "Store location: App Group container group.test.store (marker repaired: appFolderEmptyGroupHasData)"
        )
        #expect(recordedHome(marker)?.kind == .group)
    }

    // MARK: - Row 3: entitled, container unavailable, marker none or appFolder

    @Test("Row 3: no container and no group marker, so the app folder (containerUnavailable), marker=appFolder")
    func rowThreeNoContainer() throws {
        defer { cleanUp() }
        let resolved = try launch(.missing)
        #expect(isAppFolder(resolved, .containerUnavailable))
        #expect(recordedHome(marker)?.kind == .appFolder)
        #expect(resolved.homeRecord?.groupCopyURL == nil, "No group copy without a container")
    }

    @Test("Row 3: container not writable and marker=appFolder, so the app folder")
    func rowThreeNotWritable() throws {
        defer { cleanUp() }
        try marker.write(.appFolder())
        #expect(isAppFolder(try launch(.notWritable), .containerUnavailable))
    }

    // MARK: - Row 4: entitled, container unavailable, marker=group

    @Test("Row 4: marker=group and no container, so it throws and creates no empty store")
    func rowFourGroupMarker() throws {
        defer { cleanUp() }
        try marker.write(.group(Self.group))
        #expect(throws: StoreError.appGroupContainerUnavailable(.noContainer)) { try resolve(.missing) }
        #expect(throws: StoreError.appGroupContainerUnavailable(.containerNotWritable)) {
            try resolve(.notWritable)
        }
        #expect(!FileManager.default.fileExists(atPath: appFolderStore.path))
        #expect(recordedHome(marker)?.kind == .group, "The marker is left as it was")
    }

    @Test("Row 4: an unreadable marker and no container also throw, since the store may be in the group")
    func rowFourUnreadableMarker() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(
            at: marker.url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("{".utf8).write(to: marker.url)
        #expect(throws: StoreError.appGroupContainerUnavailable(.noContainer)) { try resolve(.missing) }
    }

    // MARK: - Rows 5 and 6: the store is in a group this build can't use

    @Test("Row 5: marker=group in a build that isn't entitled or names no group throws a distinct error")
    func rowFive() throws {
        defer { cleanUp() }
        try marker.write(.group(Self.group))
        #expect(throws: StoreError.storeIsInAppGroup(.notEntitled)) { try resolve(entitlement: .denied) }
        #expect(throws: StoreError.storeIsInAppGroup(.noAppGroupConfigured)) { try resolve(group: nil) }
        #expect(!FileManager.default.fileExists(atPath: appFolderStore.path), "Never a silent fallback")
    }

    @Test("Row 6: the marker's group ID differs from the configured one, so the same distinct error")
    func rowSixGroupIdentifierMismatch() throws {
        defer { cleanUp() }
        try marker.write(.group(Self.otherGroup))
        #expect(throws: StoreError.storeIsInAppGroup(.groupIdentifierChanged)) { try resolve() }
        #expect(throws: StoreError.storeIsInAppGroup(.groupIdentifierChanged)) { try resolve(.missing) }
        #expect(throws: StoreError.storeIsInAppGroup(.groupIdentifierChanged)) {
            try resolve(entitlement: .denied)
        }
        #expect(!FileManager.default.fileExists(atPath: groupStore.path))
        #expect(!FileManager.default.fileExists(atPath: appFolderStore.path))
    }

    // MARK: - Row 7: not entitled or no group

    @Test("Row 7: not entitled or no group, with no marker or marker=appFolder, so the app folder as before")
    func rowSeven() throws {
        defer { cleanUp() }
        #expect(isAppFolder(try launch(entitlement: .denied), .notEntitled))
        #expect(recordedHome(marker)?.kind == .appFolder)
        #expect(isAppFolder(try launch(group: nil), .noAppGroupConfigured))
        #expect(!FileManager.default.fileExists(atPath: container.path), "The group container is never touched")
    }

    // MARK: - Sequences across launches

    @Test("The container flapping between unavailable and available keeps the store in the app folder")
    func flappingContainerStaysInAppFolder() throws {
        defer { cleanUp() }
        #expect(isAppFolder(try launch(.missing, enteringData: true), .containerUnavailable))
        for state in [Container.available, .missing, .available, .notWritable, .available] {
            let resolved = try launch(state)
            #expect(resolved.url.standardizedFileURL == appFolderStore)
        }
        #expect(!FileManager.default.fileExists(atPath: groupStore.path))
    }

    @Test("Flapping with no data entered still stays in the app folder, because marker=appFolder")
    func flappingWithoutDataStaysInAppFolder() throws {
        defer { cleanUp() }
        try launch(.missing)
        #expect(isAppFolder(try launch(.available), .awaitingMigration))
        #expect(isAppFolder(try launch(.missing), .containerUnavailable))
    }

    @Test("Fallback creates app-folder data, then the container returns with group data: an error, never a merge")
    func containerReturnsWithGroupData() throws {
        defer { cleanUp() }
        #expect(isAppFolder(try launch(.missing, enteringData: true), .containerUnavailable))
        try putData(at: groupStore)
        #expect(throws: StoreError.storesInBothLocations) { try launch(.available) }
        #expect(try Data(contentsOf: appFolderStore) == Data("records".utf8), "Nothing is merged or deleted")
        #expect(try Data(contentsOf: groupStore) == Data("records".utf8), "Nothing is merged or deleted")
        #expect(recordedHome(marker)?.kind == .appFolder, "The marker is left as it was")
    }

    // MARK: - Extensions (read-only)

    @Test("Extension: no store-home copy in the group means no data, and nothing is created")
    func extensionWithoutCopy() throws {
        defer { cleanUp() }
        #expect(throws: StoreError.sharedStoreNotInGroup) {
            try StoreConfiguration.sharedReadOnly(
                appGroupIdentifier: Self.group,
                groupContainer: lookup(.available),
                entitlement: .granted,
            )
        }
        #expect(!FileManager.default.fileExists(atPath: container.path), "The extension never creates a folder")
    }

    @Test("Extension: a stale copy (app folder, or another group) means no data")
    func extensionWithStaleCopy() throws {
        defer { cleanUp() }
        for stale in [StoreHome.appFolder(), .group(Self.otherGroup)] {
            try groupCopy.write(stale)
            #expect(throws: StoreError.sharedStoreNotInGroup) {
                try StoreLocation.sharedStoreURL(
                    appGroupIdentifier: Self.group,
                    groupContainer: lookup(.available),
                    entitlement: .granted,
                )
            }
        }
    }

    @Test("Extension: after the app opened the group store, the extension reads it")
    func extensionAfterAppLaunch() throws {
        defer { cleanUp() }
        try launch()
        let url = try StoreLocation.sharedStoreURL(
            appGroupIdentifier: Self.group,
            groupContainer: lookup(.available),
            entitlement: .granted,
        )
        #expect(url.standardizedFileURL == groupStore)
        // Once the app's store is in the app folder, the next launch with the container updates the copy.
        try marker.write(.appFolder())
        #expect(isAppFolder(try launch(), .awaitingMigration))
        #expect(throws: StoreError.sharedStoreNotInGroup) {
            try StoreLocation.sharedStoreURL(
                appGroupIdentifier: Self.group,
                groupContainer: lookup(.available),
                entitlement: .granted,
            )
        }
    }
}

import Foundation
import Testing

@testable import LittleOrbitPersistence

/// P1: a store is only probed when the answer can change the location, and the group store first.
extension StoreHomeRuleTests {
    private func probes(
        _ state: Container = .available,
        entitlement: AppGroupEntitlementCheck = .granted,
    ) throws -> (resolved: ResolvedStoreLocation, probed: [URL]) {
        let counter = ProbeCounter()
        let resolved = try resolve(state, entitlement: entitlement, contents: counter.check)
        return (resolved, counter.probed.map(\.standardizedFileURL))
    }

    /// One launch that records the store home afterwards, as `LittleOrbitStore.makeContainer` does.
    private func probingLaunch() throws -> (resolved: ResolvedStoreLocation, probed: [URL]) {
        let launched = try probes()
        let record = try #require(launched.resolved.homeRecord)
        StoreHomeRecorder.record(record, storeURL: launched.resolved.url)
        return launched
    }

    private func putEmptyFile(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    @Test("Probes: marker=group probes nothing, even with data in both stores")
    func noProbesWithGroupMarker() throws {
        defer { cleanUp() }
        try marker.write(.group(Self.group))
        try putData(at: groupStore)
        try putData(at: appFolderStore)
        let (resolved, probed) = try probes()
        #expect(isGroup(resolved))
        #expect(probed.isEmpty)
    }

    @Test("Probes: marker=appFolder with no group store file probes nothing (the steady state before #102)")
    func noProbesWithAppFolderMarkerAndNoGroupStore() throws {
        defer { cleanUp() }
        try marker.write(.appFolder())
        try putData(at: appFolderStore)
        let (resolved, probed) = try probes()
        #expect(isAppFolder(resolved, .awaitingMigration))
        #expect(probed.isEmpty)
    }

    @Test("Probes: marker=appFolder with an empty group store probes only the group store")
    func appFolderMarkerProbesGroupOnly() throws {
        defer { cleanUp() }
        try marker.write(.appFolder())
        try putData(at: appFolderStore)
        try putEmptyFile(at: groupStore)
        let (resolved, probed) = try probes()
        #expect(isAppFolder(resolved, .awaitingMigration))
        #expect(probed == [groupStore])
    }

    @Test("Probes: marker=appFolder with group data probes the group store first, then the app folder")
    func appFolderMarkerWithGroupDataProbesBoth() throws {
        defer { cleanUp() }
        try marker.write(.appFolder())
        try putData(at: groupStore)
        try putEmptyFile(at: appFolderStore)
        let (resolved, probed) = try probes()
        #expect(resolved.repair == .appFolderEmptyGroupHasData)
        #expect(probed == [groupStore, appFolderStore])
    }

    @Test("Probes: marker=appFolder with no app-folder store file and group data probes only the group")
    func appFolderMarkerWithoutAppFolderFile() throws {
        defer { cleanUp() }
        try marker.write(.appFolder())
        try putData(at: groupStore)
        let (resolved, probed) = try probes()
        #expect(isGroup(resolved))
        #expect(probed == [groupStore])
    }

    @Test("Probes: no marker and no store files probes nothing (a fresh install)")
    func noProbesOnFreshInstall() throws {
        defer { cleanUp() }
        let (resolved, probed) = try probes()
        #expect(isGroup(resolved))
        #expect(probed.isEmpty)
    }

    @Test("Probes: no marker and only an app-folder store probes only the app folder")
    func noMarkerAppFolderOnly() throws {
        defer { cleanUp() }
        try putData(at: appFolderStore)
        let (resolved, probed) = try probes()
        #expect(resolved.repair == .noMarkerAppFolderHasData)
        #expect(probed == [appFolderStore])
    }

    @Test("Probes: no marker and both store files probes the group store first")
    func noMarkerBothFilesGroupFirst() throws {
        defer { cleanUp() }
        try putData(at: groupStore)
        try putEmptyFile(at: appFolderStore)
        let (resolved, probed) = try probes()
        #expect(resolved.repair == .noMarkerGroupHasData)
        #expect(probed == [groupStore, appFolderStore])
    }

    @Test("Probes: two launches with no marker and app-folder data probe once, then the marker stops the probe")
    func twoLaunchesAppFolder() throws {
        defer { cleanUp() }
        try putData(at: appFolderStore)
        let first = try probingLaunch()
        #expect(first.resolved.repair == .noMarkerAppFolderHasData)
        #expect(first.probed == [appFolderStore])
        #expect(recordedHome(marker)?.kind == .appFolder)
        let second = try probingLaunch()
        #expect(isAppFolder(second.resolved, .awaitingMigration))
        #expect(second.resolved.repair == nil)
        #expect(second.probed.isEmpty)
    }

    @Test("Probes: two launches with no marker and group data probe both once, then nothing")
    func twoLaunchesGroup() throws {
        defer { cleanUp() }
        try putData(at: groupStore)
        try putEmptyFile(at: appFolderStore)
        let first = try probingLaunch()
        #expect(first.resolved.repair == .noMarkerGroupHasData)
        #expect(first.probed == [groupStore, appFolderStore])
        let second = try probingLaunch()
        #expect(isGroup(second.resolved))
        #expect(second.resolved.repair == nil)
        #expect(second.probed.isEmpty)
    }

    @Test("Probes: rows 3 and 7 probe nothing")
    func noProbesWhenTheContainerIsUnavailableOrNotEntitled() throws {
        defer { cleanUp() }
        try putData(at: appFolderStore)
        #expect(try probes(.missing).probed.isEmpty)
        #expect(try probes(entitlement: .denied).probed.isEmpty)
    }
}

/// A `StoreContentsCheck` that records which stores it was asked about, answering like `fileHasBytes`.
private final class ProbeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    var probed: [URL] { lock.withLock { urls } }

    var check: StoreContentsCheck {
        StoreContentsCheck { url in
            self.lock.withLock { self.urls.append(url) }
            return StoreContentsCheck.fileHasBytes.hasData(url)
        }
    }
}

import Foundation
import Testing

@testable import LittleOrbitPersistence

/// #52: the store is in the App Group container when the app may use it, otherwise in Application Support.
@Suite("Store location (#52)")
struct StoreLocationResolutionTests {
    private static let group = "group.test.store"
    private static let bundle = "test.store.app"

    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("store-location-\(UUID().uuidString)", isDirectory: true)

    private var support: URL { root.appendingPathComponent("support", isDirectory: true) }
    private var container: URL { root.appendingPathComponent("group", isDirectory: true) }

    private func lookup(_ url: URL) -> AppGroupContainerLookup {
        AppGroupContainerLookup { $0 == Self.group ? url : nil }
    }

    private func resolve(
        group: String? = Self.group,
        lookup: AppGroupContainerLookup? = nil,
        entitlement: AppGroupEntitlementCheck = .granted,
    ) throws -> ResolvedStoreLocation {
        try StoreLocation.resolve(
            applicationSupport: support,
            bundleIdentifier: Self.bundle,
            appGroupIdentifier: group,
            groupContainer: lookup ?? self.lookup(container),
            entitlement: entitlement,
        )
    }

    private var fallbackURL: URL {
        StoreLocation.storeURL(applicationSupport: support, bundleIdentifier: Self.bundle).standardizedFileURL
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    @Test("Entitled and available: the store is in the group container, not Application Support")
    func appGroupWhenEntitled() throws {
        defer { cleanUp() }
        let resolved = try resolve()
        #expect(resolved.kind == .appGroup(identifier: Self.group))
        #expect(
            resolved.url.standardizedFileURL
                == container.appendingPathComponent("LittleOrbit.store").standardizedFileURL
        )
        #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent(Self.bundle).path))
    }

    @Test("First launch: a missing group container folder is created, the store file is left to SwiftData")
    func createsMissingGroupFolder() throws {
        defer { cleanUp() }
        #expect(!FileManager.default.fileExists(atPath: container.path))
        let resolved = try resolve()
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: container.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(!FileManager.default.fileExists(atPath: resolved.url.path))
    }

    @Test("No group ID configured: Application Support, without asking for a container")
    func noGroupConfigured() throws {
        defer { cleanUp() }
        for group in [nil, "", "  "] as [String?] {
            let failing = AppGroupContainerLookup { _ in
                Issue.record("No container lookup without a group ID")
                return nil
            }
            let resolved = try resolve(group: group, lookup: failing)
            #expect(resolved.kind == .applicationSupport(.noAppGroupConfigured))
            #expect(resolved.url.standardizedFileURL == fallbackURL)
        }
    }

    @Test("Not entitled (signing off, as on CI and the simulator): Application Support, even if a container exists")
    func notEntitled() throws {
        defer { cleanUp() }
        let resolved = try resolve(entitlement: .denied)
        #expect(resolved.kind == .applicationSupport(.notEntitled))
        #expect(resolved.url.standardizedFileURL == fallbackURL)
        #expect(!FileManager.default.fileExists(atPath: container.path), "The group container is never touched")
    }

    @Test("Entitled but no container from the system: it throws and opens no second store")
    func noContainer() {
        defer { cleanUp() }
        #expect(throws: StoreError.appGroupContainerUnavailable(.noContainer)) {
            try resolve(lookup: .unavailable)
        }
        #expect(!FileManager.default.fileExists(atPath: support.path), "No empty Application Support store")
    }

    @Test("Entitled but the group container can't be created: it throws and opens no second store")
    func containerNotWritable() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocker = root.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        #expect(throws: StoreError.appGroupContainerUnavailable(.containerNotWritable)) {
            try resolve(lookup: lookup(blocker.appendingPathComponent("group", isDirectory: true)))
        }
        #expect(!FileManager.default.fileExists(atPath: support.path), "No empty Application Support store")
    }

    @Test("The app's store throws, instead of falling back, when the entitled container is unavailable")
    func appLocalThrowsWhenEntitledContainerIsUnavailable() {
        defer { cleanUp() }
        #expect(throws: StoreError.appGroupContainerUnavailable(.noContainer)) {
            try StoreConfiguration.appLocal(
                applicationSupport: support,
                bundleIdentifier: Self.bundle,
                appGroupIdentifier: Self.group,
                groupContainer: .unavailable,
                entitlement: .granted,
            )
        }
    }

    // MARK: - iOS: the container lookup is the entitlement check

    @Test("iOS, unsigned: no container means not entitled, so it falls back with notEntitled")
    func iOSUnsignedIsNotEntitled() throws {
        defer { cleanUp() }
        let resolved = try resolve(lookup: .unavailable, entitlement: .containerPresence(.unavailable))
        #expect(resolved.kind == .applicationSupport(.notEntitled))
        #expect(resolved.url.standardizedFileURL == fallbackURL)
    }

    @Test("iOS, signed for the group: the container is there, so the store is in it")
    func iOSSignedUsesGroup() throws {
        defer { cleanUp() }
        let resolved = try resolve(entitlement: .containerPresence(lookup(container)))
        #expect(resolved.kind == .appGroup(identifier: Self.group))
    }

    @Test("iOS, signed but the container can't be created: it throws")
    func iOSSignedContainerNotWritable() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocker = root.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let broken = lookup(blocker.appendingPathComponent("group", isDirectory: true))
        #expect(throws: StoreError.appGroupContainerUnavailable(.containerNotWritable)) {
            try resolve(lookup: broken, entitlement: .containerPresence(broken))
        }
    }

    @Test("Each build always picks the same location, so data isn't reset on every launch")
    func stableAcrossLaunches() throws {
        defer { cleanUp() }
        #expect(try resolve() == resolve())
        #expect(try resolve(entitlement: .denied) == resolve(entitlement: .denied))
    }

    @Test("The App Group store and the fallback never share a file")
    func locationsDiffer() throws {
        defer { cleanUp() }
        #expect(try resolve().url != resolve(entitlement: .denied).url)
    }

    @Test("The log line names the location and the fallback reason")
    func summary() {
        #expect(
            StoreLocation.summary(of: .appGroup(identifier: Self.group))
                == "Store location: App Group container group.test.store"
        )
        #expect(
            StoreLocation.summary(of: .applicationSupport(.notEntitled))
                == "Store location: Application Support (fallback: notEntitled)"
        )
    }

    @Test("Unsigned test runner: the system check grants no group")
    func systemCheckInTests() {
        #expect(!AppGroupEntitlementCheck.system.isEntitled(Self.group))
    }

    @Test("The app's store opens for writing")
    func appLocalIsWritable() throws {
        defer { cleanUp() }
        let configuration = try StoreConfiguration.appLocal(
            applicationSupport: support,
            bundleIdentifier: Self.bundle,
            appGroupIdentifier: Self.group,
            groupContainer: lookup(container),
            entitlement: .granted,
        )
        #expect(configuration.fileURL?.deletingLastPathComponent().lastPathComponent == "group")
    }
}

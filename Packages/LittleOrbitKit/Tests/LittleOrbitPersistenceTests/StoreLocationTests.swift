import Foundation
import XCTest

@testable import LittleOrbitPersistence

final class StoreLocationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testStoreLivesInABundleFolderNotDefaultStore() {
        let url = StoreLocation.storeURL(applicationSupport: root, bundleIdentifier: "com.example.littleorbit")
        XCTAssertEqual(url.lastPathComponent, "LittleOrbit.store")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "com.example.littleorbit")
        XCTAssertEqual(
            url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL,
            root.standardizedFileURL,
        )
        XCTAssertNotEqual(url.lastPathComponent, "default.store")
    }

    func testMissingOrBlankBundleIdentifierFallsBackToAnAppFolder() {
        for identifier in [nil, "", "  "] as [String?] {
            let url = StoreLocation.storeURL(applicationSupport: root, bundleIdentifier: identifier)
            XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "LittleOrbit")
        }
    }

    func testPreparingCreatesTheFolderOnceAndIsRepeatable() throws {
        let url = try StoreLocation.prepareStoreURL(
            applicationSupport: root,
            bundleIdentifier: "com.example.littleorbit",
            appGroupIdentifier: nil,
        )
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDirectory)
        )
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "Only the folder is created; the store is SwiftData's",
        )
        XCTAssertEqual(
            try StoreLocation.prepareStoreURL(
                applicationSupport: root,
                bundleIdentifier: "com.example.littleorbit",
                appGroupIdentifier: nil,
            ),
            url,
        )
    }

    func testAppLocalConfigurationPointsAtThePreparedURL() throws {
        let configuration = try StoreConfiguration.appLocal(
            applicationSupport: root,
            bundleIdentifier: "com.example.littleorbit",
            appGroupIdentifier: nil,
        )
        XCTAssertEqual(configuration.sync, .none)
        XCTAssertFalse(configuration.inMemory)
        XCTAssertEqual(configuration.fileURL?.lastPathComponent, "LittleOrbit.store")
    }

    // MARK: - App Group with fallback (Kiran's answer on #82)

    private func lookup(_ containers: [String: URL]) -> AppGroupContainerLookup {
        AppGroupContainerLookup { containers[$0] }
    }

    func testAppGroupContainerIsUsedWhenTheGroupIsConfiguredAndAvailable() throws {
        let container = root.appendingPathComponent("group", isDirectory: true)
        let url = try StoreLocation.prepareStoreURL(
            applicationSupport: root.appendingPathComponent("support", isDirectory: true),
            bundleIdentifier: "com.example.littleorbit",
            appGroupIdentifier: "group.com.example.littleorbit",
            groupContainer: lookup(["group.com.example.littleorbit": container]),
            entitlement: .granted,
        )
        XCTAssertEqual(
            url.standardizedFileURL,
            container.appendingPathComponent("LittleOrbit.store").standardizedFileURL,
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: container.path))
    }

    func testAnEntitledBuildWithoutItsGroupContainerThrowsInsteadOfFallingBack() {
        let support = root.appendingPathComponent("support", isDirectory: true)
        XCTAssertThrowsError(
            try StoreLocation.prepareStoreURL(
                applicationSupport: support,
                bundleIdentifier: "com.example.littleorbit",
                appGroupIdentifier: "group.com.example.littleorbit",
                groupContainer: .unavailable,
                entitlement: .granted,
            )
        ) { error in
            XCTAssertEqual(error as? StoreError, .appGroupContainerUnavailable(.noContainer))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.path))
    }

    func testNoOrBlankGroupIDNeverAsksForAContainer() {
        for identifier in [nil, "", "   "] as [String?] {
            let lookup = AppGroupContainerLookup { _ in
                XCTFail("No container lookup without a group ID")
                return nil
            }
            XCTAssertNil(StoreLocation.groupStoreURL(appGroupIdentifier: identifier, lookup: lookup))
        }
    }

    func testTheGroupIDIsReadFromInfoPlist() {
        let key = StoreLocation.appGroupInfoKey
        XCTAssertEqual(key, "LittleOrbitAppGroupIdentifier")
        XCTAssertEqual(
            StoreLocation.appGroupIdentifier(infoDictionary: [key: " group.com.example.littleorbit "]),
            "group.com.example.littleorbit",
        )
        XCTAssertNil(StoreLocation.appGroupIdentifier(infoDictionary: nil))
        XCTAssertNil(StoreLocation.appGroupIdentifier(infoDictionary: [:]))
        XCTAssertNil(StoreLocation.appGroupIdentifier(infoDictionary: [key: ""]))
        XCTAssertNil(StoreLocation.appGroupIdentifier(infoDictionary: [key: 42]))
    }

    func testAppLocalConfigurationUsesTheGroupContainerWhenAvailable() throws {
        let container = root.appendingPathComponent("group", isDirectory: true)
        let configuration = try StoreConfiguration.appLocal(
            applicationSupport: root,
            bundleIdentifier: "com.example.littleorbit",
            appGroupIdentifier: "group.com.example.littleorbit",
            groupContainer: lookup(["group.com.example.littleorbit": container]),
            entitlement: .granted,
        )
        XCTAssertEqual(configuration.fileURL?.deletingLastPathComponent().lastPathComponent, "group")
    }
}

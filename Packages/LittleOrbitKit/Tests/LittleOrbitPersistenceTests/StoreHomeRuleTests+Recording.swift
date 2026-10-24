import Foundation
import Testing

@testable import LittleOrbitPersistence

/// Writing the store-home marker and the store ID, and what the store logs (#52).
extension StoreHomeRuleTests {
    // MARK: - Writing the marker

    @Test("The marker is written only when it changes")
    func markerWrittenOnlyOnChange() {
        let store = CountingMarkerStore()
        let identifier = UUID()
        let first = StoreHomeRecorder.record(.group(Self.group), storeID: identifier, marker: store, groupCopy: nil)
        let second = StoreHomeRecorder.record(.group(Self.group), storeID: identifier, marker: store, groupCopy: nil)
        #expect(first == StoreHomeRecordOutcome(marker: .written, groupCopy: .skipped))
        #expect(second == StoreHomeRecordOutcome(marker: .unchanged, groupCopy: .skipped))
        #expect(store.writes == 1)
        StoreHomeRecorder.record(.appFolder(), storeID: identifier, marker: store, groupCopy: nil)
        #expect(store.writes == 2)
    }

    @Test("Repeated launches leave the marker file untouched")
    func repeatedLaunchesDontRewrite() throws {
        defer { cleanUp() }
        try launch()
        let before = try Data(contentsOf: marker.url)
        let resolved = try resolve()
        let outcome = StoreHomeRecorder.record(try #require(resolved.homeRecord), storeURL: resolved.url)
        #expect(outcome == StoreHomeRecordOutcome(marker: .unchanged, groupCopy: .unchanged))
        #expect(try Data(contentsOf: marker.url) == before)
    }

    @Test("A marker write failure is reported, never thrown, and the launch goes on")
    func markerWriteFailureDoesntFailTheLaunch() throws {
        defer { cleanUp() }
        let outcome = StoreHomeRecorder.record(
            .group(Self.group),
            storeID: UUID(),
            marker: FailingMarkerStore(),
            groupCopy: FailingMarkerStore(),
        )
        #expect(outcome == StoreHomeRecordOutcome(marker: .failed, groupCopy: .failed))
        // On disk: a folder where the marker file goes makes the write fail; the next launch still opens.
        try FileManager.default.createDirectory(at: marker.url, withIntermediateDirectories: true)
        let resolved = try resolve()
        let fileOutcome = StoreHomeRecorder.record(try #require(resolved.homeRecord), storeURL: resolved.url)
        #expect(fileOutcome.marker == .failed)
        #expect(isGroup(try resolve()))
    }

    @Test("The store ID is created once and kept")
    func storeIdentityIsStable() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        #expect(StoreIdentity.read(forStoreAt: groupStore) == nil)
        let first = StoreIdentity.readOrCreate(forStoreAt: groupStore)
        #expect(first.event == .created)
        let second = StoreIdentity.readOrCreate(forStoreAt: groupStore)
        #expect(second.identifier == first.identifier)
        #expect(second.event == .kept)
    }

    @Test("An unreadable store ID file is replaced, and the change is reported and logged")
    func unreadableStoreIdentityIsReplacedAndLogged() throws {
        defer { cleanUp() }
        let resolved = try launch()
        let original = try #require(StoreIdentity.read(forStoreAt: resolved.url))
        try Data("not a uuid".utf8).write(to: StoreIdentity.url(forStoreAt: resolved.url))
        let outcome = StoreHomeRecorder.record(try #require(resolved.homeRecord), storeURL: resolved.url)
        #expect(outcome.storeID == .replacedUnreadable)
        let replacement = try #require(StoreIdentity.read(forStoreAt: resolved.url))
        #expect(replacement != original)
        #expect(recordedHome(marker)?.storeID == replacement)
        #expect(outcome.marker == .written, "The marker follows the new ID")
        #expect(StoreHomeRecorder.summary(of: outcome).hasSuffix(", store ID replacedUnreadable"))
    }

    @Test("A store holds data only when its file has bytes (the Linux and test check)")
    func fileHasBytes() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        #expect(!StoreContentsCheck.fileHasBytes.hasData(groupStore))
        FileManager.default.createFile(atPath: groupStore.path, contents: Data())
        #expect(!StoreContentsCheck.fileHasBytes.hasData(groupStore))
        try putData(at: groupStore)
        #expect(StoreContentsCheck.fileHasBytes.hasData(groupStore))
    }

    // MARK: - Logs

    @Test("Log lines carry reasons only, never a path")
    func logsHaveNoPaths() {
        let reasons: [StoreFallbackReason] = [
            .noAppGroupConfigured, .notEntitled, .containerUnavailable, .awaitingMigration,
        ]
        for reason in reasons {
            let line = StoreLocation.summary(of: .applicationSupport(reason))
            #expect(line == "Store location: Application Support (fallback: \(reason.rawValue))")
            #expect(!line.contains("/"))
        }
        let outcome = StoreHomeRecordOutcome(marker: .failed, groupCopy: .skipped, storeID: .unavailable)
        let line = StoreHomeRecorder.summary(of: outcome)
        #expect(line == "Store home: marker failed, group copy skipped, store ID unavailable")
        #expect(!line.contains("/"))
        let repairs: [StoreHomeRepair] = [
            .appFolderEmptyGroupHasData, .noMarkerGroupHasData, .noMarkerAppFolderHasData, .unreadableMarker,
        ]
        for repair in repairs {
            let resolved = ResolvedStoreLocation(
                url: URL(fileURLWithPath: "/private/path/LittleOrbit.store"),
                kind: .appGroup(identifier: Self.group),
                repair: repair,
            )
            let repaired = StoreLocation.summary(of: resolved)
            #expect(repaired.hasSuffix("(marker repaired: \(repair.rawValue))"))
            #expect(!repaired.contains("/"))
        }
    }
}

/// Counts writes, for "written only when it changes".
private final class CountingMarkerStore: StoreHomeMarkerStore, @unchecked Sendable {
    private let lock = NSLock()
    private var home: StoreHome?
    private var count = 0

    var writes: Int { lock.withLock { count } }

    func read() -> StoreHomeMarkerState {
        lock.withLock { home.map(StoreHomeMarkerState.recorded) ?? .missing }
    }

    func write(_ home: StoreHome) throws {
        lock.withLock {
            self.home = home
            count += 1
        }
    }
}

/// A marker store whose writes always fail.
private struct FailingMarkerStore: StoreHomeMarkerStore {
    struct WriteFailed: Error {}

    func read() -> StoreHomeMarkerState { .missing }

    func write(_ home: StoreHome) throws {
        throw WriteFailed()
    }
}

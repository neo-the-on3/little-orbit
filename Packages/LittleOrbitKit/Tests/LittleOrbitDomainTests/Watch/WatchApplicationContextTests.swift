import Foundation
import Testing

@testable import LittleOrbitDomain

/// The application context's publish stamp, beside the snapshot (Tester F1, Tech Architect 5647974743).
@Suite("Watch application context")
struct WatchApplicationContextTests {
    typealias Codec = WatchMessageCodecTests

    @Test("Stamps always grow, even when the clock goes back, and start from the clock")
    func stampsGrow() {
        var stamps = WatchPublishStamp()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = stamps.next(now: now)
        #expect(first == 1_800_000_000_000)
        #expect(stamps.next(now: now) == first + 1)
        #expect(stamps.next(now: now.addingTimeInterval(-3_600)) == first + 2)
        #expect(stamps.next(now: now.addingTimeInterval(10)) == first + 10_000)
    }

    @Test("The watch reads the snapshot and ignores the stamp; the snapshot's version stays 1")
    func stampOutsideSnapshot() throws {
        let data = try WatchMessageCodec.encode(Codec.snapshot)
        let context = WatchLinkKeys.applicationContext(WatchApplicationContext(snapshot: data, stamp: 42))
        #expect(context.count == 2)
        let read = try #require(WatchLinkKeys.snapshot(in: context))
        #expect(read == data)
        #expect(try WatchMessageCodec.decodeSnapshot(read) == Codec.snapshot)
        #expect(WatchSnapshot.currentVersion == 1)
        // An older iPhone build's context, with no stamp, still reads.
        #expect(WatchLinkKeys.snapshot(in: [WatchLinkKeys.snapshot: data]) == data)
    }

    @Test("The stamp counts in the 48 KB cap: a snapshot at its limit plus the stamp stays within it")
    func stampInCap() throws {
        let long = String(repeating: "Long description ", count: 20)
        var snapshot = Codec.snapshot
        snapshot.scheduled = (1...400).map { Codec.occurrence($0 % 28 + 1, .upcoming, name: "\($0) \(long)") }
        let data = try WatchMessageCodec.encode(snapshot, limit: WatchApplicationContext.snapshotLimit)
        #expect(data.count <= WatchApplicationContext.snapshotLimit)
        let context = WatchLinkKeys.applicationContext(WatchApplicationContext(snapshot: data, stamp: .max))
        let encoded = try PropertyListSerialization.data(fromPropertyList: context, format: .binary, options: 0)
        #expect(encoded.count <= WatchMessageCodec.maxSnapshotBytes)
    }

    @Test("A request's user info carries the request and its ID")
    func userInfo() throws {
        let id = UUID()
        let info = WatchLinkKeys.userInfo(request: Data("r".utf8), id: id)
        #expect(WatchLinkKeys.request(in: info) == Data("r".utf8))
        #expect(WatchLinkKeys.requestID(in: info) == id)
        #expect(WatchLinkKeys.request(in: [:]) == nil)
        #expect(WatchLinkKeys.requestID(in: [WatchLinkKeys.requestID: "nonsense"]) == nil)
    }
}

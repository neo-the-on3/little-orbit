import Foundation
import Testing

@testable import LittleOrbitDomain

/// The watch side (#197 item 10): sending Pay and Skip, the syncing state, and reading the iPhone's answers from
/// the next snapshot. The cache is disposable (D345).
@MainActor
@Suite("Watch Scheduled use cases")
struct WatchScheduledUseCasesTests {
    typealias Codec = WatchMessageCodecTests

    @MainActor
    final class FakeLink: WatchPhoneLink {
        var latest: Data?
        var sent: [Data] = []
        private var handler: (@MainActor (Data) -> Void)?

        func latestSnapshotData() -> Data? { latest }
        func onSnapshot(_ handler: @escaping @MainActor (Data) -> Void) { self.handler = handler }
        func send(_ request: Data) { sent.append(request) }

        func deliver(_ snapshot: WatchSnapshot) throws {
            let data = try WatchMessageCodec.encode(snapshot)
            latest = data
            handler?(data)
        }

        func sentRequests() throws -> [WatchScheduledRequest] {
            try sent.map { try WatchMessageCodec.decodeRequest($0) }
        }
    }

    let link = FakeLink()
    let cache = InMemoryWatchScheduledCache()
    let watchToday = CalendarDay(year: 2026, month: 10, day: 20)

    func useCases() -> DefaultWatchScheduledUseCases {
        DefaultWatchScheduledUseCases(link: link, cache: cache, today: { [watchToday] in watchToday })
    }

    @Test("No snapshot yet: nothing to list")
    func waiting() {
        #expect(useCases().state() == WatchScheduledState())
    }

    @Test("Pay queues one request for the iPhone, dated the day it was tapped, and shows it pending")
    func paySends() throws {
        try link.deliver(Codec.snapshot)
        let watch = useCases()
        var changes = 0
        watch.onChange { changes += 1 }
        let row = Codec.snapshot.scheduled[0]
        watch.pay(row)
        // A second tap while it syncs does nothing, Pay or Skip.
        watch.pay(row)
        watch.skip(row)
        let requests = try link.sentRequests()
        #expect(requests.count == 1)
        #expect(requests[0].action == .pay && requests[0].occurrence == row.day && requests[0].tappedOn == watchToday)
        #expect(watch.state().sent.map(\.isPending) == [true])
        #expect(changes == 1)
    }

    @Test("The iPhone applied it: the next snapshot clears the pending mark")
    func appliedClears() throws {
        try link.deliver(Codec.snapshot)
        let watch = useCases()
        watch.skip(Codec.snapshot.scheduled[1])
        let request = try #require(try link.sentRequests().first)
        var next = Codec.snapshot
        next.scheduled.removeLast()
        next.outcomes = [WatchRequestOutcome(requestID: request.id, result: .applied)]
        try link.deliver(next)
        #expect(watch.state().sent.isEmpty)
        #expect(watch.state().snapshot == next)
    }

    @Test(
        "Turned down on the iPhone: the answer stays until OK, then goes",
        arguments: [
            WatchRequestResult.alreadyPaid, .alreadySkipped, .deleted,
        ],
    )
    func conflictStaysUntilAcknowledged(_ result: WatchRequestResult) throws {
        try link.deliver(Codec.snapshot)
        let watch = useCases()
        watch.pay(Codec.snapshot.scheduled[0])
        let request = try #require(try link.sentRequests().first)
        var next = Codec.snapshot
        next.outcomes = [WatchRequestOutcome(requestID: request.id, result: result)]
        try link.deliver(next)
        #expect(watch.state().sent.map(\.result) == [result])
        // The same answer in a later snapshot changes nothing.
        try link.deliver(next)
        #expect(watch.state().sent.count == 1)
        watch.acknowledge(requestID: request.id)
        #expect(watch.state().sent.isEmpty)
        #expect(cache.sentRequests().isEmpty)
    }

    @Test("Stale or unsupported: nothing happened, and the row shows as the iPhone has it, with no message")
    func staleDropsQuietly() throws {
        try link.deliver(Codec.snapshot)
        let watch = useCases()
        watch.pay(Codec.snapshot.scheduled[0])
        watch.skip(Codec.snapshot.scheduled[1])
        let requests = try link.sentRequests()
        var next = Codec.snapshot
        next.outcomes = [
            WatchRequestOutcome(requestID: requests[0].id, result: .stale),
            WatchRequestOutcome(requestID: requests[1].id, result: .unsupported),
        ]
        try link.deliver(next)
        #expect(watch.state().sent.isEmpty)
    }

    @Test("A snapshot with no answer yet keeps the request pending")
    func noAnswerKeepsPending() throws {
        try link.deliver(Codec.snapshot)
        let watch = useCases()
        watch.pay(Codec.snapshot.scheduled[0])
        try link.deliver(Codec.snapshot)
        #expect(watch.state().sent.map(\.isPending) == [true])
    }

    @Test("A snapshot from a newer iPhone build, or one that can’t be read, is ignored and the cache kept")
    func newerSnapshotIgnored() throws {
        try link.deliver(Codec.snapshot)
        let watch = useCases()
        var newer = Codec.snapshot
        newer.version = WatchSnapshot.currentVersion + 1
        newer.scheduled = []
        try link.deliver(newer)
        #expect(watch.state().snapshot == Codec.snapshot)
        #expect(try cache.snapshotData().map { try WatchMessageCodec.decodeSnapshot($0) } == Codec.snapshot)
    }

    @Test("Relaunched with the iPhone away: the cached list and the pending Pay come back from the cache")
    func relaunchFromCache() throws {
        try link.deliver(Codec.snapshot)
        useCases().pay(Codec.snapshot.scheduled[0])
        link.latest = nil
        let relaunched = useCases()
        #expect(relaunched.state().snapshot == Codec.snapshot)
        #expect(relaunched.state().sent.map(\.isPending) == [true])
    }
}

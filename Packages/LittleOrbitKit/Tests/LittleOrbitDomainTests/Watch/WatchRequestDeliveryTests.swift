import Foundation
import Testing

@testable import LittleOrbitDomain

/// D377: a watch Pay or Skip is never dropped. Failed deliveries are retried less often each time, up to a ceiling,
/// on activation, reachability and app activation, with one send in flight per request; the row stays syncing.
@MainActor
@Suite("Watch request delivery")
struct WatchRequestDeliveryTests {
    typealias Codec = WatchMessageCodecTests
    typealias FakeLink = WatchScheduledUseCasesTests.FakeLink

    let link = FakeLink()
    let cache = InMemoryWatchScheduledCache()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// The use cases over a clock the test moves, recording each timer they ask for.
    final class Timeline {
        var now: Date
        var timers: [(TimeInterval, @MainActor () -> Void)] = []

        init(_ now: Date) {
            self.now = now
        }
    }

    func useCases(_ timeline: Timeline) -> DefaultWatchScheduledUseCases {
        DefaultWatchScheduledUseCases(
            link: link,
            cache: cache,
            today: { CalendarDay(year: 2026, month: 10, day: 20) },
            now: { timeline.now },
            schedule: { delay, action in timeline.timers.append((delay, action)) },
        )
    }

    @Test("The wait doubles after each failure up to a ceiling, and never ends")
    func policy() {
        #expect(WatchRetryPolicy.delay(afterFailures: 1) == WatchRetryPolicy.first)
        #expect(WatchRetryPolicy.delay(afterFailures: 2) == WatchRetryPolicy.first * 2)
        #expect(WatchRetryPolicy.delay(afterFailures: 3) == WatchRetryPolicy.first * 4)
        #expect(WatchRetryPolicy.delay(afterFailures: 20) == WatchRetryPolicy.ceiling)
        #expect(WatchRetryPolicy.delay(afterFailures: 10_000) == WatchRetryPolicy.ceiling)
    }

    @Test("Repeated failures back off but never drop the request; the row stays syncing")
    func failuresBackOffNeverDrop() throws {
        try link.deliver(Codec.snapshot)
        let timeline = Timeline(start)
        let watch = useCases(timeline)
        watch.pay(Codec.snapshot.scheduled[0])
        let id = try #require(watch.state().sent.first?.id)
        var waits: [TimeInterval] = []
        for _ in 0..<12 {
            link.finish(id, delivered: false)
            let wait = try #require(timeline.timers.last?.0)
            waits.append(wait)
            // Triggers before the wait is over send nothing.
            let before = link.sent.count
            link.canRetry()
            watch.retryPending()
            #expect(link.sent.count == before)
            timeline.now = timeline.now.addingTimeInterval(wait)
            timeline.timers.last?.1()
            #expect(link.sent.count == before + 1)
        }
        #expect(waits == waits.sorted())
        #expect(waits.first == WatchRetryPolicy.first && waits.last == WatchRetryPolicy.ceiling)
        // Still there, still pending, in the cache too.
        #expect(watch.state().sent.map(\.isPending) == [true])
        #expect(cache.sentRequests().first?.failures == 12)
        #expect(try link.sentRequests().allSatisfy { $0.id == id })
    }

    @Test("Reachability, activation or the app opening retries a request whose wait is over")
    func triggersRetry() throws {
        try link.deliver(Codec.snapshot)
        let timeline = Timeline(start)
        let watch = useCases(timeline)
        watch.skip(Codec.snapshot.scheduled[1])
        let id = try #require(watch.state().sent.first?.id)
        link.finish(id, delivered: false)
        timeline.now = timeline.now.addingTimeInterval(WatchRetryPolicy.first)
        link.canRetry()
        #expect(link.sent.count == 2)
        link.finish(id, delivered: false)
        timeline.now = timeline.now.addingTimeInterval(WatchRetryPolicy.first * 2)
        watch.retryPending()
        #expect(link.sent.count == 3)
    }

    @Test(
        "One send in flight per request, however many triggers; delivered ones aren’t sent again, even after relaunch"
    )
    func oneInFlight() throws {
        try link.deliver(Codec.snapshot)
        let timeline = Timeline(start)
        let watch = useCases(timeline)
        watch.pay(Codec.snapshot.scheduled[0])
        let id = try #require(watch.state().sent.first?.id)
        for _ in 0..<5 {
            link.canRetry()
            watch.retryPending()
        }
        #expect(link.sent.count == 1)
        link.finish(id, delivered: true)
        link.canRetry()
        #expect(link.sent.count == 1)
        // Delivered but not answered yet: still syncing on the watch.
        #expect(watch.state().sent.first?.isPending == true)
        let relaunched = useCases(timeline)
        link.canRetry()
        relaunched.retryPending()
        #expect(link.sent.count == 1)
    }

    @Test("Relaunched with a request not delivered yet: it goes out again, once")
    func relaunchResends() throws {
        try link.deliver(Codec.snapshot)
        let timeline = Timeline(start)
        link.isActive = false
        useCases(timeline).pay(Codec.snapshot.scheduled[0])
        link.isActive = true
        let relaunched = useCases(timeline)
        link.canRetry()
        relaunched.retryPending()
        #expect(link.sent.count == 1)
        #expect(relaunched.state().sent.map(\.isPending) == [true])
    }

    @Test("A cache written before D377 still reads, as not delivered")
    func olderCacheReads() throws {
        let sent = WatchSentRequest(
            request: WatchScheduledRequest(
                action: .pay,
                itemID: UUID(),
                occurrence: CalendarDay(year: 2026, month: 10, day: 20),
                tappedOn: CalendarDay(year: 2026, month: 10, day: 20),
            ),
            occurrence: Codec.snapshot.scheduled[0],
        )
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(sent)) as? [String: Any])
        json.removeValue(forKey: "isDelivered")
        json.removeValue(forKey: "failures")
        let older = try JSONSerialization.data(withJSONObject: json)
        let read = try JSONDecoder().decode(WatchSentRequest.self, from: older)
        #expect(read.id == sent.id && !read.isDelivered && read.failures == 0 && read.retryAfter == nil)
    }
}

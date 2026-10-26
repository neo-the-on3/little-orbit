import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// The watch → iPhone `transferUserInfo` path, which the simulator pair can't deliver (Tester's checks 4–7, 9, 10
/// and 15), over the fake sessions with the real dictionaries (Tech Architect 5647974743). There's no
/// `sendMessage` fallback: one delivery path, settled exactly once.
@MainActor
@Suite("Watch Pay and Skip over user info, end to end")
struct WatchUserInfoPathTests {
    let scene: ScheduledScene
    let sessions = FakeWatchSessions()
    let link: PhoneWatchLink
    let inbox = InMemoryWatchRequestInboxStore()
    let today = CalendarDay(year: 2026, month: 10, day: 20)
    var plan: ScheduledItem

    /// The watch use cases' clock and the timers they ask for (D377).
    final class Timeline {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var timers: [(TimeInterval, @MainActor () -> Void)] = []
    }

    let timeline = Timeline()

    init() throws {
        scene = try ScheduledScene()
        link = PhoneWatchLink(session: sessions)
        sessions.phoneLink = link
        plan = scene.item("Phone Plan", day: 20, month: 10)
        try scene.add(plan)
    }

    func phone() -> WatchPhoneFeature {
        let useCases = DefaultWatchPhoneUseCases(
            repository: scene.repository,
            inbox: inbox,
            today: { [today] in today },
        )
        let phone = WatchPhoneFeature(snapshots: useCases, requests: useCases, link: link, updates: scene.updates)
        link.activationCompleted()
        phone.start()
        return phone
    }

    func watch() -> (WatchScheduledViewModel, DefaultWatchScheduledUseCases) {
        let timeline = timeline
        let useCases = DefaultWatchScheduledUseCases(
            link: sessions,
            cache: InMemoryWatchScheduledCache(),
            today: { [today] in today },
            now: { timeline.now },
            schedule: { delay, action in timeline.timers.append((delay, action)) },
        )
        return (WatchScheduledViewModel(useCases: useCases, locale: Locale(identifier: "en_IN")), useCases)
    }

    func posted() throws -> [Transaction] {
        try scene.repository.scheduleLedger().transactions.filter { $0.scheduledTemplateID == plan.id }
    }

    func queuedRequest() throws -> WatchScheduledRequest {
        let info = try #require(sessions.outstanding.first)
        return try WatchMessageCodec.decodeRequest(try #require(WatchLinkKeys.request(in: info)))
    }

    @Test("A Pay is encoded as user info, received and settled by occurrence and revision; repeated, it records once")
    func settlesOnceByOccurrenceAndRevision() throws {
        let phone = phone()
        defer { withExtendedLifetime(phone) {} }
        let (watch, _) = watch()
        let row = try #require(watch.rows.first)
        watch.pay(row.id)
        let request = try queuedRequest()
        #expect(request.action == .pay)
        #expect(request.itemID == plan.id)
        #expect(request.occurrence == today && request.tappedOn == today)
        #expect(request.revision == WatchItemRevision.of(plan))
        #expect(watch.rows.first?.dateText == "Paid · syncing")

        sessions.deliver(times: 3)
        #expect(try posted().count == 1)
        #expect(inbox.notices().isEmpty)
        // The answer rides back in the next stamped context and clears the mark.
        #expect(watch.rows.map(\.dateText).allSatisfy { $0 != "Paid · syncing" })
        #expect(watch.conflict == nil)
        // Delivered again later, from a relaunch: still one.
        let again = WatchLinkKeys.userInfo(request: try WatchMessageCodec.encode(request), id: request.id)
        link.received(userInfo: again)
        #expect(try posted().count == 1)
    }

    @Test("Edited on the iPhone before the Pay arrived: nothing recorded, one IDs-only notice (D374)")
    func staleRaisesNotice() throws {
        let phone = phone()
        defer { withExtendedLifetime(phone) {} }
        let (watch, _) = watch()
        watch.pay(try #require(watch.rows.first).id)
        let request = try queuedRequest()
        var edited = plan
        edited.amount = 1_500
        try scene.add(edited)
        sessions.deliver()
        #expect(try posted().isEmpty)
        let notice = try #require(inbox.notices().first)
        #expect(inbox.notices().count == 1)
        #expect(notice == WatchRequestNotice(id: request.id, reason: .itemChanged, action: .pay, itemID: plan.id))
        // IDs only: exactly the request ID, reason, action and item ID, so the name and amount aren't stored. The
        // IDs are random, so the stored text is compared whole rather than searched for "1500", which the two random
        // UUIDs contain about once in 2,200 runs (#253).
        let stored = try JSONDecoder().decode([[String: String]].self, from: try JSONEncoder().encode(inbox.notices()))
        #expect(stored == [["q": request.id.uuidString, "r": "itemChanged", "a": "pay", "i": plan.id.uuidString]])
        #expect(watch.conflict == nil)
    }

    @Test("A request from a newer watch build is refused: nothing recorded, answered unsupported, one notice (D376)")
    func newerVersionRefused() throws {
        let phone = phone()
        defer { withExtendedLifetime(phone) {} }
        let id = UUID()
        let newer = Data("{\"v\":2,\"q\":\"\(id.uuidString)\",\"a\":\"pay\",\"later\":true}".utf8)
        link.received(userInfo: WatchLinkKeys.userInfo(request: newer, id: id))
        #expect(try posted().isEmpty)
        #expect(inbox.keptRequests().isEmpty)
        #expect(inbox.outcomes() == [WatchRequestOutcome(requestID: id, result: .unsupported)])
        #expect(inbox.notices().map(\.reason) == [.newerWatchApp])
        let snapshot = try WatchMessageCodec.decodeSnapshot(try #require(sessions.latestSnapshotData()))
        #expect(snapshot.outcomes.contains(WatchRequestOutcome(requestID: id, result: .unsupported)))
    }

    @Test("A failed transfer stays queued and syncing, is retried after its wait, once, and records once (D377)")
    func failedTransferRetries() throws {
        let phone = phone()
        defer { withExtendedLifetime(phone) {} }
        let (watch, useCases) = watch()
        watch.pay(try #require(watch.rows.first).id)
        #expect(sessions.transfers == 1)
        sessions.failTransfers()
        #expect(try posted().isEmpty)
        #expect(watch.rows.first?.dateText == "Paid · syncing")
        #expect(useCases.state().sent.count == 1)
        // Before the wait is over, triggers send nothing; after it, reachability sends it again, once.
        sessions.canRetry()
        #expect(sessions.transfers == 1)
        timeline.now = timeline.now.addingTimeInterval(WatchRetryPolicy.first)
        sessions.canRetry()
        sessions.canRetry()
        watch.appBecameActive()
        #expect(sessions.transfers == 2)
        #expect(sessions.outstanding.count == 1)
        sessions.deliver()
        #expect(try posted().count == 1)
        #expect(watch.rows.map(\.dateText).allSatisfy { $0 != "Paid · syncing" })
    }
}

import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D378 over the fake sessions (Tech Architect 5647974743): a watch Pay that arrives as user info and that the
/// ledger refuses for good is answered `refused`, leaves both queues, raises one IDs-only `refusedOnSave` notice
/// and is never retried. A refused Skip needs a repository that refuses the settle, so it's covered in Domain
/// (`WatchRequestRefusalTests`).
@MainActor
@Suite("Watch requests refused for good, over user info")
struct WatchRefusalUserInfoPathTests {
    let scene: ScheduledScene
    let sessions = FakeWatchSessions()
    let link: PhoneWatchLink
    let inbox = InMemoryWatchRequestInboxStore()
    let today = CalendarDay(year: 2026, month: 10, day: 20)
    let plan: ScheduledItem

    final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    let clock = Clock()

    init() throws {
        scene = try ScheduledScene()
        link = PhoneWatchLink(session: sessions)
        sessions.phoneLink = link
        plan = scene.item("Phone Plan", day: 20, month: 10)
        try scene.add(plan)
    }

    @Test("A refused Pay: nothing recorded, answered refused, one IDs-only notice, gone from both queues, no retry")
    func refusedPayOverUserInfo() throws {
        let useCases = DefaultWatchPhoneUseCases(
            repository: scene.repository,
            inbox: inbox,
            today: { [today] in today },
        )
        let phone = WatchPhoneFeature(snapshots: useCases, requests: useCases, link: link, updates: scene.updates)
        defer { withExtendedLifetime(phone) {} }
        link.activationCompleted()
        phone.start()
        let clock = clock
        let watchUseCases = DefaultWatchScheduledUseCases(
            link: sessions,
            cache: InMemoryWatchScheduledCache(),
            today: { [today] in today },
            now: { clock.now },
            schedule: { _, _ in },
        )
        let watch = WatchScheduledViewModel(useCases: watchUseCases, locale: Locale(identifier: "en_IN"))
        watch.pay(try #require(watch.rows.first).id)
        let info = try #require(sessions.outstanding.first)
        let request = try WatchMessageCodec.decodeRequest(try #require(WatchLinkKeys.request(in: info)))

        // The item's category goes from the ledger without the item changing, so its save is refused, not stale.
        var ledger = try scene.repository.ledgerSnapshot()
        ledger.categories.removeAll { $0.id == plan.categoryID }
        try scene.repository.replaceLedger(with: ledger)
        sessions.deliver(times: 2)

        #expect(try scene.repository.scheduleLedger().transactions.isEmpty)
        #expect(inbox.keptRequests().isEmpty)
        #expect(inbox.outcomes() == [WatchRequestOutcome(requestID: request.id, result: .refused)])
        #expect(
            inbox.notices() == [
                WatchRequestNotice(id: request.id, reason: .refusedOnSave, action: .pay, itemID: plan.id)
            ]
        )
        let stored = try #require(String(bytes: try JSONEncoder().encode(inbox.notices()), encoding: .utf8))
        #expect(!stored.contains("Phone Plan"))
        // The watch clears its mark quietly and drops the request from its queue.
        #expect(watch.conflict == nil)
        #expect(watch.rows.map(\.dateText).allSatisfy { !$0.hasSuffix("· syncing") })
        #expect(watchUseCases.state().sent.isEmpty)
        // Never sent again, however much time passes or how often the iPhone comes back.
        clock.now = clock.now.addingTimeInterval(WatchRetryPolicy.ceiling * 4)
        sessions.canRetry()
        watch.appBecameActive()
        #expect(sessions.transfers == 1)
        // A relaunch on the iPhone doesn't retry it either.
        phone.start()
        #expect(try scene.repository.scheduleLedger().transactions.isEmpty)
        #expect(inbox.notices().count == 1)
    }
}

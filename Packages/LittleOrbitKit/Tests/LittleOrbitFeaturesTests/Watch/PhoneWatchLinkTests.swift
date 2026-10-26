import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tester F1 (Tech Architect 5647974743): a watch app installed or reinstalled after the iPhone published gets the
/// list with no ledger change, though the session drops an identical context; a stale pre-activation install flag
/// doesn't count as delivered.
@MainActor
@Suite("iPhone application context over a session that drops identical contexts")
struct PhoneWatchLinkTests {
    let scene: ScheduledScene
    let sessions = FakeWatchSessions()
    let link: PhoneWatchLink
    let today = CalendarDay(year: 2026, month: 10, day: 20)

    init() throws {
        scene = try ScheduledScene()
        link = PhoneWatchLink(session: sessions)
        sessions.phoneLink = link
        try scene.add(scene.item("Phone Plan", day: 20, month: 10))
    }

    func phone() -> WatchPhoneFeature {
        let useCases = DefaultWatchPhoneUseCases(
            repository: scene.repository,
            inbox: InMemoryWatchRequestInboxStore(),
            today: { [today] in today },
        )
        return WatchPhoneFeature(snapshots: useCases, requests: useCases, link: link, updates: scene.updates)
    }

    func watch() -> WatchScheduledViewModel {
        let useCases = DefaultWatchScheduledUseCases(
            link: sessions,
            cache: InMemoryWatchScheduledCache(),
            today: { [today] in today },
        )
        return WatchScheduledViewModel(useCases: useCases, locale: Locale(identifier: "en_IN"))
    }

    @Test("Installed after the iPhone published: the stamped context reaches the new watch app")
    func installAfterPublish() throws {
        sessions.watchHasApp = false
        sessions.watchState.isWatchAppInstalled = false
        let phone = phone()
        defer { withExtendedLifetime(phone) {} }
        link.activationCompleted()
        phone.start()
        #expect(sessions.accepted.isEmpty)

        sessions.installWatchApp()
        #expect(sessions.accepted.count == 1)
        #expect(sessions.dropped == 0)
        #expect(sessions.watchContext?[WatchLinkKeys.stamp] != nil)
        let watch = watch()
        #expect(watch.rows.first?.title == "Phone Plan")
    }

    @Test("Reinstalled: the same snapshot goes again with a new stamp, so the session doesn't drop it")
    func reinstall() throws {
        let phone = phone()
        defer { withExtendedLifetime(phone) {} }
        link.activationCompleted()
        phone.start()
        #expect(sessions.accepted.count == 1)
        let first = try #require(sessions.accepted.first)

        sessions.removeWatchApp()
        #expect(sessions.latestSnapshotData() == nil)
        sessions.installWatchApp()
        #expect(sessions.accepted.count == 2)
        #expect(sessions.dropped == 0)
        let second = try #require(sessions.accepted.last)
        #expect(WatchLinkKeys.snapshot(in: second) == WatchLinkKeys.snapshot(in: first))
        #expect(sessions.stamps == sessions.stamps.sorted() && Set(sessions.stamps).count == 2)
        #expect(watch().rows.first?.title == "Phone Plan")
        // Unstamped, the re-send would have been byte-identical and dropped, which is F1.
        try sessions.updateApplicationContext(second)
        #expect(sessions.dropped == 1)
    }

    @Test("A stale install flag before activation counts for nothing; activation is when the state is known")
    func staleFlagBeforeActivation() throws {
        // The session still says installed from an earlier install, but the app isn't on the watch.
        sessions.watchHasApp = false
        let phone = phone()
        defer { withExtendedLifetime(phone) {} }
        phone.start()
        #expect(sessions.accepted.isEmpty)

        // Activation says it isn't installed: still nothing, and nothing was taken as delivered.
        sessions.watchState.isWatchAppInstalled = false
        link.activationCompleted()
        #expect(sessions.accepted.isEmpty)
        phone.start()
        #expect(sessions.accepted.isEmpty)

        sessions.installWatchApp()
        #expect(sessions.accepted.count == 1)
        #expect(watch().rows.first?.title == "Phone Plan")
    }

    @Test("Activation with the app installed sends a stamped context, even one identical to before")
    func activationResends() throws {
        let phone = phone()
        defer { withExtendedLifetime(phone) {} }
        phone.start()
        #expect(sessions.accepted.isEmpty)
        link.activationCompleted()
        #expect(sessions.accepted.count == 1)
        // Another watch: the session deactivates, then activates for it.
        link.deactivated()
        sessions.watchHasApp = true
        link.activationCompleted()
        #expect(sessions.accepted.count == 2)
        #expect(sessions.dropped == 0)
    }

    @Test("Ledger changes keep the content dedupe; a state change that isn't pairing or install sends nothing")
    func dedupeKept() throws {
        let phone = phone()
        defer { withExtendedLifetime(phone) {} }
        link.activationCompleted()
        phone.start()
        phone.publish()
        phone.start()
        #expect(sessions.accepted.count == 1)
        try scene.add(scene.item("Gym", day: 22, month: 10))
        phone.publish()
        #expect(sessions.accepted.count == 2)
        // sessionWatchStateDidChange for something else, such as a complication: same pairing and install.
        link.watchStateChanged()
        #expect(sessions.accepted.count == 2)
        // Unpaired: nothing can go, and nothing is sent.
        sessions.watchState.isPaired = false
        link.watchStateChanged()
        phone.publish()
        #expect(sessions.accepted.count == 2)
        sessions.watchState.isPaired = true
        link.watchStateChanged()
        #expect(sessions.accepted.count == 3)
    }
}

import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// The iPhone and the watch end to end over fake WatchConnectivity links (#197 item 10): the phone's snapshot,
/// a watch Pay applied once through the store, and the answer coming back.
@MainActor
@Suite("Watch and iPhone, end to end")
struct WatchPhoneFeatureTests {
    /// A paired session: the iPhone's context reaches the watch, and the watch's requests queue until the iPhone
    /// is reachable, then arrive once each, as `transferUserInfo` does.
    @MainActor
    final class Pair: WatchCompanionLink, WatchPhoneLink {
        var phoneIsReachable = true
        private var context: Data?
        private var queued: [Data] = []
        private var phoneHandler: (@MainActor (Data) -> Void)?
        private var watchHandler: (@MainActor (Data) -> Void)?
        var publishes = 0
        /// No paired watch or no watch app yet: the next publish is held, not delivered.
        var holdsNext = false

        // iPhone side
        func onRequest(_ handler: @escaping @MainActor (Data) -> Void) { phoneHandler = handler }
        func publish(_ snapshot: Data) throws -> WatchPublishResult {
            if holdsNext {
                holdsNext = false
                return .waiting
            }
            publishes += 1
            context = snapshot
            watchHandler?(snapshot)
            return .delivered
        }

        // Watch side
        func latestSnapshotData() -> Data? { context }
        func onSnapshot(_ handler: @escaping @MainActor (Data) -> Void) { watchHandler = handler }
        func send(_ request: Data) {
            queued.append(request)
            deliver()
        }

        func onActivated(_ handler: @escaping @MainActor () -> Void) {}

        func deliver() {
            guard phoneIsReachable else {
                return
            }
            let batch = queued
            queued = []
            for request in batch {
                phoneHandler?(request)
            }
        }
    }

    let scene: ScheduledScene
    let pair = Pair()
    let inbox = InMemoryWatchRequestInboxStore()

    init() throws {
        scene = try ScheduledScene()
    }

    func phone() -> WatchPhoneFeature {
        let useCases = DefaultWatchPhoneUseCases(
            repository: scene.repository,
            inbox: inbox,
            today: { [scene] in
                TransactionTiming.today(scene.now, timeZone: TimeZone(identifier: ScheduledScene.zone)!)
            },
        )
        return WatchPhoneFeature(snapshots: useCases, requests: useCases, link: pair, updates: scene.updates)
    }

    func watch(today: CalendarDay) -> WatchScheduledViewModel {
        let useCases = DefaultWatchScheduledUseCases(
            link: pair,
            cache: InMemoryWatchScheduledCache(),
            today: { today },
        )
        return WatchScheduledViewModel(useCases: useCases, locale: Locale(identifier: "en_IN"))
    }

    @Test("Paid on the watch with the iPhone off on 20 Oct, booted on 21 Oct: recorded once, dated 20 Oct")
    func payWhileIPhoneAway() throws {
        // Phone Plan, manual, on the 20th; today is 20 Oct.
        let plan = scene.item("Phone Plan", day: 20, month: 10)
        try scene.add(plan)
        let phone = phone()
        phone.start()
        let watch = watch(today: CalendarDay(year: 2026, month: 10, day: 20))
        let row = try #require(watch.rows.first)
        #expect(row.title == "Phone Plan" && row.dateText == "Today")

        pair.phoneIsReachable = false
        watch.pay(row.id)
        #expect(watch.rows.first?.dateText == "Paid · syncing")

        // The next day the iPhone boots: the queued request arrives once, even if the system repeats it.
        scene.now = ScheduledScene.date(CalendarDay(year: 2026, month: 10, day: 21))
        let revision = scene.updates.revision
        pair.phoneIsReachable = true
        pair.deliver()
        let posted = try scene.repository.scheduleLedger().transactions.filter { $0.scheduledTemplateID == plan.id }
        #expect(posted.count == 1)
        let day = try #require(posted.first.map { TransactionCalendar.ownDay(of: $0.date, timeZoneID: $0.timeZoneID) })
        #expect(day == CalendarDay(year: 2026, month: 10, day: 20))
        #expect(scene.updates.revision > revision)
        // The watch got the answer: no syncing mark and no message; the row is now the next occurrence.
        #expect(watch.conflict == nil)
        #expect(watch.rows.map(\.dateText).allSatisfy { $0 != "Paid · syncing" })
        #expect(watch.rows.first?.occurrence.day == CalendarDay(year: 2026, month: 11, day: 20))
    }

    @Test("Paid on the watch offline and skipped on the iPhone: the skip stays, and the watch says so (#32 QA)")
    func skippedOnIPhoneWins() throws {
        let plan = scene.item("StreamBox", day: 20, month: 10)
        try scene.add(plan)
        let phone = phone()
        phone.start()
        let watch = watch(today: CalendarDay(year: 2026, month: 10, day: 20))
        pair.phoneIsReachable = false
        watch.pay(try #require(watch.rows.first).id)
        try scene.useCases.manage.skip(itemID: plan.id, occurrence: CalendarDay(year: 2026, month: 10, day: 20))
        pair.phoneIsReachable = true
        pair.deliver()
        #expect(try scene.repository.scheduleLedger().transactions.isEmpty)
        let conflict = try #require(watch.conflict)
        #expect(conflict.title == "Already skipped on iPhone")
        #expect(
            conflict.message
                == "StreamBox · 20 Oct. Your Pay from the watch wasn’t recorded, and Everyday Savings is unchanged."
        )
        watch.closeConflict()
        #expect(watch.conflict == nil)
    }

    @Test("The same snapshot isn’t sent twice; a ledger change sends a new one")
    func publishesOnlyChanges() throws {
        try scene.add(scene.item("Rent", day: 1, month: 11))
        let phone = phone()
        phone.start()
        phone.publish()
        #expect(pair.publishes == 1)
        try scene.add(scene.item("Gym", day: 5, month: 11))
        phone.publish()
        #expect(pair.publishes == 2)
    }

    @Test("A snapshot the link held (no watch yet) isn’t taken as sent: the next start publishes it (5646845418 B1)")
    func heldSnapshotIsPublishedAgain() throws {
        try scene.add(scene.item("Rent", day: 1, month: 11))
        pair.holdsNext = true
        let phone = phone()
        phone.start()
        #expect(pair.publishes == 0)
        // Nothing changed in the ledger, but the watch has nothing yet.
        phone.start()
        #expect(pair.publishes == 1)
        #expect(pair.latestSnapshotData() != nil)
        phone.start()
        #expect(pair.publishes == 1)
    }

    @Test("A request the iPhone can’t read is reported with no user data, and changes nothing")
    func unreadableRequest() throws {
        var problems: [String] = []
        let useCases = DefaultWatchPhoneUseCases(
            repository: scene.repository,
            inbox: inbox,
            today: { CalendarDay(year: 2026, month: 10, day: 20) },
        )
        let phone = WatchPhoneFeature(snapshots: useCases, requests: useCases, link: pair) { problem in
            problems.append("\(problem)")
        }
        phone.received(Data("{\"v\":9}".utf8))
        phone.received(Data("nonsense".utf8))
        #expect(problems == ["newerRequest", "unreadableRequest"])
    }

    @Test("Paid on the watch, then the item edited on the iPhone: nothing recorded, one card that survives a relaunch")
    func staleCardSurvivesRelaunch() throws {
        let name = "watch-feature-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        func launch() -> (WatchPhoneFeature, WatchRequestNoticeViewModel) {
            let useCases = DefaultWatchPhoneUseCases(
                repository: scene.repository,
                inbox: UserDefaultsWatchRequestInbox(defaults: defaults),
                today: { CalendarDay(year: 2026, month: 10, day: 20) },
            )
            let notices = WatchRequestNoticeViewModel(useCases: useCases)
            let phone = WatchPhoneFeature(
                snapshots: useCases,
                requests: useCases,
                link: pair,
                updates: scene.updates,
                notices: notices,
            )
            return (phone, notices)
        }
        var plan = scene.item("Phone Plan", day: 20, month: 10)
        try scene.add(plan)
        let (phone, notices) = launch()
        phone.start()
        let watch = watch(today: CalendarDay(year: 2026, month: 10, day: 20))
        pair.phoneIsReachable = false
        watch.pay(try #require(watch.rows.first).id)
        plan.amount = 1_500
        try scene.add(plan)
        #expect(notices.card == nil)
        pair.phoneIsReachable = true
        pair.deliver()
        #expect(try scene.repository.scheduleLedger().transactions.isEmpty)
        // The watch just clears its syncing mark (D374).
        #expect(watch.conflict == nil)
        #expect(watch.rows.map(\.dateText).allSatisfy { $0 != "Paid · syncing" })
        #expect(notices.card?.title == "Couldn’t Record Watch Payment")
        #expect(notices.card?.itemID == plan.id)

        let (_, relaunched) = launch()
        #expect(relaunched.card?.title == "Couldn’t Record Watch Payment")
        relaunched.dismiss()
        #expect(launch().1.card == nil)
    }

    @Test("A request from a newer watch app: nothing recorded, the watch clears its mark, an update card (D376)")
    func newerWatchAppCard() throws {
        try scene.add(scene.item("Phone Plan", day: 20, month: 10))
        let useCases = DefaultWatchPhoneUseCases(
            repository: scene.repository,
            inbox: inbox,
            today: { CalendarDay(year: 2026, month: 10, day: 20) },
        )
        let notices = WatchRequestNoticeViewModel(useCases: useCases)
        let phone = WatchPhoneFeature(snapshots: useCases, requests: useCases, link: pair, notices: notices)
        phone.start()
        let id = UUID()
        phone.received(Data("{\"v\":2,\"q\":\"\(id.uuidString)\",\"a\":\"skip\"}".utf8))
        #expect(try scene.repository.scheduleLedger().transactions.isEmpty)
        #expect(inbox.keptRequests().isEmpty)
        #expect(inbox.outcomes() == [WatchRequestOutcome(requestID: id, result: .unsupported)])
        #expect(notices.card?.title == "Update little-orbit on iPhone")
        #expect(
            notices.card?.message.hasPrefix("Your Apple Watch has a newer version of little-orbit, so this skip")
                == true
        )
    }
}

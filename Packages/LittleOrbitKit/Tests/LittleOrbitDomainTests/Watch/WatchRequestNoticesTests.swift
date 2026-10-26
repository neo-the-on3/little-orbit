import Foundation
import Testing

@testable import LittleOrbitDomain

/// D374 and D376: a watch Pay or Skip made against an item that changed on the iPhone first, or sent by a newer
/// watch build, records and skips nothing, on its own day or any other, and leaves one notice per request until
/// it's dismissed.
@MainActor
@Suite("Watch requests the iPhone doesn’t apply")
struct WatchRequestNoticesTests {
    typealias Fixture = ScheduledFixture
    typealias Scene = WatchPhoneUseCasesTests.Scene

    /// The request the watch sends for the plan's 20 Oct row of the snapshot it has now.
    func watchRequest(_ action: WatchScheduledRequest.Action, in scene: Scene) throws -> WatchScheduledRequest {
        let row = try #require(
            try scene.useCases.snapshot().scheduled
                .first {
                    $0.itemID == scene.plan.id && $0.day == Fixture.day(2026, 10, 20)
                }
        )
        #expect(row.revision != nil)
        return WatchScheduledRequest(
            action: action,
            itemID: row.itemID,
            occurrence: row.day,
            tappedOn: Fixture.day(2026, 10, 20),
            revision: row.revision,
        )
    }

    /// Changes the plan on the iPhone, as its edit form does.
    func edit(_ scene: Scene, _ change: (inout ScheduledItem) -> Void) throws {
        var item = try #require(scene.repository.base.snapshot.scheduledItems.first { $0.id == scene.plan.id })
        change(&item)
        try scene.repository.saveScheduledItem(item, today: scene.today, now: Fixture.date(2026, 10, 21))
    }

    var settledDays: (Scene) -> [CalendarDay] {
        { scene in
            scene.repository.base.snapshot.scheduledItems.first { $0.id == scene.plan.id }?
                .occurrences.filter(\.outcome.isSettled).map(\.day) ?? []
        }
    }

    @Test("A stale Pay records nothing and queues one notice")
    func stalePay() throws {
        let scene = try Scene()
        let request = try watchRequest(.pay, in: scene)
        try edit(scene) { $0.amount = 899 }
        let run = scene.useCases.receive(request)
        #expect(run.outcomes == [WatchRequestOutcome(requestID: request.id, result: .stale)])
        #expect(!run.changedLedger && run.queuedNotices == 1)
        #expect(scene.posted.isEmpty && settledDays(scene).isEmpty)
        let notices = scene.useCases.pendingNotices()
        #expect(
            notices.map(\.notice) == [
                WatchRequestNotice(id: request.id, reason: .itemChanged, action: .pay, itemID: scene.plan.id)
            ]
        )
        #expect(notices.first?.item?.details == "Rent" && notices.first?.item?.categoryName == "Housing")
    }

    @Test("A stale Skip skips nothing and queues one notice")
    func staleSkip() throws {
        let scene = try Scene()
        let request = try watchRequest(.skip, in: scene)
        try edit(scene) { $0.accountID = Fixture.fundID }
        #expect(scene.useCases.receive(request).outcomes.last?.result == .stale)
        #expect(settledDays(scene).isEmpty)
        #expect(scene.inbox.notices().map(\.action) == [.skip])
    }

    @Test("A stale request is never applied to another occurrence, after the schedule moved")
    func neverAnotherOccurrence() throws {
        let scene = try Scene()
        let pay = try watchRequest(.pay, in: scene)
        // Moved from the 20th to the 21st: 21 Oct is now due, and 20 Oct only stays as a kept unpaid day.
        try edit(scene) { $0.startDay = Fixture.day(2026, 8, 21) }
        #expect(scene.useCases.receive(pay).outcomes.last?.result == .stale)
        // An older request with no revision, for a day that's no longer an occurrence at all.
        let old = scene.request(.skip, day: 19)
        #expect(scene.useCases.receive(old).outcomes.last?.result == .stale)
        #expect(scene.posted.isEmpty && settledDays(scene).isEmpty)
        #expect(scene.inbox.notices().count == 2)
    }

    @Test("Settling another occurrence on the iPhone doesn’t make a watch request stale")
    func otherOccurrenceSettledIsntAChange() throws {
        let scene = try Scene()
        let request = try watchRequest(.pay, in: scene)
        _ = try scene.repository.settleScheduledOccurrence(
            .skip(itemID: scene.plan.id, occurrence: Fixture.day(2026, 9, 20))
        )
        #expect(scene.useCases.receive(request).outcomes.last?.result == .applied)
        #expect(scene.posted.count == 1 && scene.inbox.notices().isEmpty)
    }

    @Test("Delivered again, a stale request queues no second notice; dismissed, it never comes back")
    func oneNoticePerRequest() throws {
        let scene = try Scene()
        let request = try watchRequest(.pay, in: scene)
        try edit(scene) { $0.details = "Flat Rent" }
        scene.useCases.receive(request)
        #expect(scene.useCases.receive(request).queuedNotices == 0)
        #expect(scene.useCases.pendingNotices().map(\.id) == [request.id])
        // The name is the item's name now.
        #expect(scene.useCases.pendingNotices().first?.item?.details == "Flat Rent")
        scene.useCases.dismissNotices([request.id])
        #expect(scene.useCases.pendingNotices().isEmpty)
        scene.useCases.receive(request)
        #expect(scene.useCases.pendingNotices().isEmpty)
    }

    @Test("An item-changed notice goes when the item is deleted afterwards")
    func noticeOfDeletedItemDrops() throws {
        let scene = try Scene()
        let request = try watchRequest(.pay, in: scene)
        try edit(scene) { $0.amount = 899 }
        scene.useCases.receive(request)
        try scene.repository.deleteScheduledItem(id: scene.plan.id)
        #expect(scene.useCases.pendingNotices().isEmpty)
        #expect(scene.inbox.notices().isEmpty)
    }

    @Test("Deleted on the iPhone still answers Deleted on iPhone (D342, D343), with no notice")
    func deletedKeepsItsAnswer() throws {
        let scene = try Scene()
        let request = try watchRequest(.skip, in: scene)
        try scene.repository.deleteScheduledItem(id: scene.plan.id)
        let run = scene.useCases.receive(request)
        #expect(run.outcomes.last?.result == .deleted && run.queuedNotices == 0)
        #expect(scene.inbox.notices().isEmpty)
    }

    @Test("A request from a newer watch build: answered unsupported, nothing kept or applied, one notice (D376)")
    func newerWatchApp() throws {
        let scene = try Scene()
        let id = UUID()
        let run = scene.useCases.receiveNewer(WatchNewerRequest(id: id, action: .skip))
        #expect(run.outcomes == [WatchRequestOutcome(requestID: id, result: .unsupported)])
        #expect(run.queuedNotices == 1)
        #expect(scene.useCases.receiveNewer(WatchNewerRequest(id: id, action: .skip)).queuedNotices == 0)
        #expect(scene.inbox.keptRequests().isEmpty && settledDays(scene).isEmpty)
        #expect(
            scene.useCases.pendingNotices().map(\.notice) == [
                WatchRequestNotice(id: id, reason: .newerWatchApp, action: .skip, itemID: nil)
            ]
        )
        #expect(
            try scene.useCases.snapshot().outcomes.last == WatchRequestOutcome(requestID: id, result: .unsupported)
        )
        // One that decoded with a newer version is answered the same way.
        var pay = scene.request(.pay, day: 20)
        pay.version = WatchSnapshot.currentVersion + 1
        scene.useCases.receive(pay)
        #expect(scene.inbox.notices().map(\.reason) == [.newerWatchApp, .newerWatchApp])
        #expect(scene.posted.isEmpty)
    }

    @Test("The codec reads a newer request’s ID and action, and only a newer one’s")
    func newerRequestProbe() throws {
        let id = UUID()
        let newer = Data("{\"v\":2,\"q\":\"\(id.uuidString)\",\"a\":\"pay\",\"z\":[1]}".utf8)
        #expect(WatchMessageCodec.newerRequest(newer) == WatchNewerRequest(id: id, action: .pay))
        let unknownAction = Data("{\"v\":3,\"q\":\"\(id.uuidString)\",\"a\":\"snooze\"}".utf8)
        #expect(WatchMessageCodec.newerRequest(unknownAction) == WatchNewerRequest(id: id, action: nil))
        let current = try WatchMessageCodec.encode(
            WatchScheduledRequest(
                action: .pay,
                itemID: id,
                occurrence: Fixture.day(2026, 10, 20),
                tappedOn: Fixture.day(2026, 10, 20),
            )
        )
        #expect(WatchMessageCodec.newerRequest(current) == nil)
        #expect(WatchMessageCodec.newerRequest(Data("{\"v\":2}".utf8)) == nil)
    }

    @Test("The revision round-trips in the snapshot and the request, and an older message without it still reads")
    func revisionOnTheWire() throws {
        let scene = try Scene()
        let request = try watchRequest(.pay, in: scene)
        #expect(try WatchMessageCodec.decodeRequest(WatchMessageCodec.encode(request)) == request)
        // An older watch build sends no "h".
        var older = request
        older.revision = nil
        let data = try WatchMessageCodec.encode(older)
        #expect(String(bytes: data, encoding: .utf8)?.contains("\"h\"") == false)
        #expect(try WatchMessageCodec.decodeRequest(data).revision == nil)
    }
}

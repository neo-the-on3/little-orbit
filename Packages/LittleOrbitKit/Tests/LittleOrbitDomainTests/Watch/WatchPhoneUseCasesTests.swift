import Foundation
import Testing

@testable import LittleOrbitDomain

/// The iPhone applying the watch's Pay and Skip (#197 item 10, #32 D345): exactly once, through the same path as
/// Pay Now and Skip, and what the iPhone already did wins.
@MainActor
@Suite("Watch requests on the iPhone")
struct WatchPhoneUseCasesTests {
    typealias Fixture = ScheduledFixture

    /// Phone Plan, a manual monthly expense on the 20th since August; today on the iPhone is 21 Oct.
    @MainActor
    final class Scene {
        let repository: FlakyScheduleRepository
        let inbox: InMemoryWatchRequestInboxStore
        var today = Fixture.day(2026, 10, 21)
        let plan: ScheduledItem

        init() throws {
            repository = FlakyScheduleRepository(FakeScheduleRepository())
            inbox = InMemoryWatchRequestInboxStore()
            repository.base.now = Fixture.date(2026, 10, 21)
            plan = Fixture.rent(amount: 799, start: Fixture.day(2026, 8, 20), automatic: false)
            try repository.saveScheduledItem(plan, today: Fixture.day(2026, 7, 1), now: Fixture.created)
        }

        var useCases: DefaultWatchPhoneUseCases {
            DefaultWatchPhoneUseCases(repository: repository, inbox: inbox, today: { [unowned self] in self.today })
        }

        func request(_ action: WatchScheduledRequest.Action, day: Int, tapped: Int = 20, month: Int = 10)
            -> WatchScheduledRequest
        {
            WatchScheduledRequest(
                action: action,
                itemID: plan.id,
                occurrence: Fixture.day(2026, month, day),
                tappedOn: Fixture.day(2026, 10, tapped),
            )
        }

        var posted: [Transaction] { repository.base.posted(for: plan.id) }

        func outcome(on day: Int) -> ScheduledOutcome? {
            repository.base.snapshot.scheduledItems.first { $0.id == plan.id }?
                .occurrence(on: Fixture.day(2026, 10, day))?
                .outcome
        }
    }

    @Test("Paid on the watch on 20 Oct, delivered on 21 Oct: one transaction, dated 20 Oct, applied once (#48)")
    func payAppliedOnceDatedWhenTapped() throws {
        let scene = try Scene()
        let request = scene.request(.pay, day: 20, tapped: 20)
        let run = scene.useCases.receive(request)
        #expect(run.outcomes == [WatchRequestOutcome(requestID: request.id, result: .applied)])
        #expect(run.changedLedger)
        let posted = try #require(scene.posted.first)
        #expect(scene.posted.count == 1)
        #expect(
            TransactionCalendar.ownDay(of: posted.date, timeZoneID: posted.timeZoneID) == Fixture.day(2026, 10, 20)
        )
        #expect(posted.id == ScheduledKey.transactionID(item: scene.plan.id, day: Fixture.day(2026, 10, 20)))
        #expect(scene.outcome(on: 20) == .posted)
    }

    @Test("The same request delivered twice records once, and its first answer is reported again")
    func duplicateDelivery() throws {
        let scene = try Scene()
        let request = scene.request(.pay, day: 20)
        scene.useCases.receive(request)
        let again = scene.useCases.receive(request)
        #expect(again.outcomes == [WatchRequestOutcome(requestID: request.id, result: .applied)])
        #expect(!again.changedLedger)
        #expect(scene.posted.count == 1)
        #expect(scene.inbox.keptRequests().isEmpty)
    }

    @Test("Paid on the iPhone first: a watch Pay or Skip records nothing and reads Already paid on iPhone")
    func alreadyPaid() throws {
        let scene = try Scene()
        _ = try scene.repository.settleScheduledOccurrence(
            .pay(itemID: scene.plan.id, occurrence: Fixture.day(2026, 10, 20), postedOn: Fixture.day(2026, 10, 21))
        )
        let pay = scene.request(.pay, day: 20)
        let skip = scene.request(.skip, day: 20)
        #expect(scene.useCases.receive(pay).outcomes.last?.result == .alreadyPaid)
        #expect(scene.useCases.receive(skip).outcomes.last?.result == .alreadyPaid)
        #expect(scene.posted.count == 1)
        #expect(scene.outcome(on: 20) == .posted)
    }

    @Test("Skipped on the iPhone, then paid on the watch offline: the skip stays and nothing is recorded (#32 QA)")
    func alreadySkipped() throws {
        let scene = try Scene()
        _ = try scene.repository.settleScheduledOccurrence(
            .skip(itemID: scene.plan.id, occurrence: Fixture.day(2026, 10, 20))
        )
        let run = scene.useCases.receive(scene.request(.pay, day: 20))
        #expect(run.outcomes.last?.result == .alreadySkipped)
        #expect(!run.changedLedger)
        #expect(scene.posted.isEmpty)
        #expect(scene.outcome(on: 20) == .skipped)
    }

    @Test("Deleted on the iPhone, or its account deleted: nothing is recorded and it reads Deleted on iPhone")
    func deleted() throws {
        let scene = try Scene()
        try scene.repository.deleteScheduledItem(id: scene.plan.id)
        #expect(scene.useCases.receive(scene.request(.pay, day: 20)).outcomes.last?.result == .deleted)
        #expect(scene.posted.isEmpty)

        let other = try Scene()
        other.repository.base.snapshot.accounts.removeAll { $0.id == Fixture.savingsID }
        #expect(other.useCases.receive(other.request(.skip, day: 20)).outcomes.last?.result == .deleted)
    }

    @Test("A day that’s no longer an occurrence (the schedule changed) records nothing and is stale")
    func stale() throws {
        let scene = try Scene()
        let run = scene.useCases.receive(scene.request(.pay, day: 19))
        #expect(run.outcomes.last?.result == .stale)
        #expect(scene.posted.isEmpty)
        #expect(scene.inbox.keptRequests().isEmpty)
    }

    @Test("A request from a newer watch build is answered unsupported and applies nothing")
    func newerRequest() throws {
        let scene = try Scene()
        var request = scene.request(.pay, day: 20)
        request.version = WatchSnapshot.currentVersion + 1
        #expect(scene.useCases.receive(request).outcomes.last?.result == .unsupported)
        #expect(scene.posted.isEmpty)
    }

    @Test("A Skip from the watch skips once and records nothing")
    func skipApplied() throws {
        let scene = try Scene()
        let run = scene.useCases.receive(scene.request(.skip, day: 20))
        #expect(run.outcomes.last?.result == .applied)
        #expect(scene.outcome(on: 20) == .skipped)
        #expect(scene.posted.isEmpty)
    }

    @Test("A failed save keeps the request; the next activation applies it, once")
    func failedSaveIsKept() throws {
        let scene = try Scene()
        scene.repository.failNextSettle = true
        let request = scene.request(.pay, day: 20)
        let first = scene.useCases.receive(request)
        #expect(first.failedCount == 1 && first.outcomes.isEmpty)
        #expect(scene.inbox.keptRequests() == [request])
        #expect(scene.posted.isEmpty)
        let retry = scene.useCases.applyKept()
        #expect(retry.outcomes == [WatchRequestOutcome(requestID: request.id, result: .applied)])
        #expect(scene.posted.count == 1)
        #expect(scene.inbox.keptRequests().isEmpty)
    }

    @Test("The snapshot lists each overdue occurrence on its own, then due today, with the outcomes")
    func snapshotRows() throws {
        let scene = try Scene()
        // Rent starts today, the 21st; Phone Plan was missed on 20 Aug, 20 Sep and 20 Oct.
        let rent = Fixture.rent(start: Fixture.day(2026, 10, 21), automatic: false)
        try scene.repository.saveScheduledItem(rent, today: Fixture.day(2026, 7, 1), now: Fixture.created)
        let request = scene.request(.skip, day: 20, month: 8)
        scene.useCases.receive(request)
        let snapshot = try scene.useCases.snapshot()
        #expect(snapshot.version == WatchSnapshot.currentVersion)
        #expect(snapshot.today == Fixture.day(2026, 10, 21))
        #expect(snapshot.scheduled.map(\.status) == [.overdue, .overdue, .dueToday])
        #expect(snapshot.scheduled.prefix(2).map(\.day) == [Fixture.day(2026, 9, 20), Fixture.day(2026, 10, 20)])
        let first = try #require(snapshot.scheduled.first)
        #expect(first.itemID == scene.plan.id && first.amount == 799 && first.currencyCode == "INR")
        #expect(first.details == "Rent" && first.categoryName == "Housing" && first.accountName == "Everyday Savings")
        #expect(snapshot.outcomes == [WatchRequestOutcome(requestID: request.id, result: .applied)])
    }

    @Test("A watch Pay of a transfer between currencies records both amounts, through the same path (#207 9.2)")
    func transferBetweenCurrencies() throws {
        let scene = try Scene()
        let wallet = Account(name: "USD Wallet", currencyCode: "USD", createdAt: Fixture.created)
        scene.repository.base.snapshot.accounts.append(wallet)
        let transfer = ScheduledItem(
            type: .transfer,
            amount: 8_400,
            destinationAmount: 100,
            receivedCurrencyCode: "USD",
            accountID: Fixture.savingsID,
            transferAccountID: wallet.id,
            startDay: Fixture.day(2026, 10, 20),
            timeZoneID: Fixture.zone,
            createdAt: Fixture.created,
        )
        scene.repository.base.snapshot.scheduledItems.append(transfer)
        let request = WatchScheduledRequest(
            action: .pay,
            itemID: transfer.id,
            occurrence: Fixture.day(2026, 10, 20),
            tappedOn: Fixture.day(2026, 10, 20),
        )
        #expect(scene.useCases.receive(request).outcomes.last?.result == .applied)
        let posted = try #require(scene.repository.base.posted(for: transfer.id).first)
        #expect(posted.amount == 8_400 && posted.destinationAmount == 100 && posted.transferAccountID == wallet.id)
        let snapshot = try scene.useCases.snapshot()
        // Paid: its next occurrence is the one listed.
        #expect(snapshot.scheduled.first { $0.itemID == transfer.id }?.day == Fixture.day(2026, 11, 20))
        #expect(snapshot.scheduled.first { $0.itemID == transfer.id }?.transferAccountName == "USD Wallet")
    }
}

/// The fake repository, with a settle that can fail once, as a full disk or a store error would, or be refused
/// for good, as the ledger's own validation would (D378).
@MainActor
final class FlakyScheduleRepository: ScheduleRepository {
    let base: FakeScheduleRepository
    var failNextSettle = false
    var refuseSettle: LedgerValidationError?

    struct SaveFailed: Error {}

    init(_ base: FakeScheduleRepository) {
        self.base = base
    }

    func scheduleLedger() throws -> LedgerSnapshot { try base.scheduleLedger() }

    func saveScheduledItem(_ item: ScheduledItem, today: CalendarDay, now: Date) throws {
        try base.saveScheduledItem(item, today: today, now: now)
    }

    func saveScheduledItem(
        _ item: ScheduledItem,
        payee: ScheduledPendingPayee?,
        today: CalendarDay,
        now: Date,
    ) throws -> ScheduledItemSaveChange {
        try base.saveScheduledItem(item, payee: payee, today: today, now: now)
    }

    func updateScheduledItem(
        _ item: ScheduledItem,
        payee: ScheduledPendingPayee?,
        today: CalendarDay,
        now: Date,
    ) throws -> ScheduledItemSaveChange {
        try base.updateScheduledItem(item, payee: payee, today: today, now: now)
    }

    func revertScheduledItemSave(_ change: ScheduledItemSaveChange, undone: Bool) throws -> ScheduledItemSaveRevert {
        try base.revertScheduledItemSave(change, undone: undone)
    }

    func updateScheduledOccurrence(
        _ item: ScheduledItem,
        editing save: ScheduledOccurrenceSave,
        payee: ScheduledPendingPayee?,
        today: CalendarDay,
        now: Date,
    ) throws -> ScheduledItemSaveChange {
        try base.updateScheduledOccurrence(item, editing: save, payee: payee, today: today, now: now)
    }

    func deleteScheduledItem(id: UUID) throws { try base.deleteScheduledItem(id: id) }

    func settleScheduledOccurrence(_ settlement: ScheduledSettlement) throws -> ScheduledSettlementChange? {
        if failNextSettle {
            failNextSettle = false
            throw SaveFailed()
        }
        if let refuseSettle {
            throw refuseSettle
        }
        return try base.settleScheduledOccurrence(settlement)
    }

    func unsettleScheduledOccurrence(_ change: ScheduledSettlementChange) throws -> ScheduledSettlementRevert {
        try base.unsettleScheduledOccurrence(change)
    }

    func resettleScheduledOccurrence(_ change: ScheduledSettlementChange) throws -> ScheduledSettlementRevert {
        try base.resettleScheduledOccurrence(change)
    }

    func catchUpScheduledItems(today: CalendarDay, pruningOrphans: Bool, holding: Set<UUID>) throws
        -> ScheduledCatchUp
    {
        try base.catchUpScheduledItems(today: today, pruningOrphans: pruningOrphans, holding: holding)
    }
}

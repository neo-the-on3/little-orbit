import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The watch's Scheduled list, Pay screen, syncing marks and messages (#32 Watch Scheduled
/// frames; D342, D343), mapped from the use case's state.
@MainActor
@Suite("Watch Scheduled view model")
struct WatchScheduledViewModelTests {
    @MainActor
    final class FakeWatchScheduled: WatchScheduledUseCase {
        var current = WatchScheduledState()
        var paid: [WatchScheduledOccurrence] = []
        var skipped: [WatchScheduledOccurrence] = []
        var acknowledged: [UUID] = []
        private var handlers: [@MainActor () -> Void] = []

        func state() -> WatchScheduledState { current }
        func pay(_ occurrence: WatchScheduledOccurrence) { paid.append(occurrence) }
        func skip(_ occurrence: WatchScheduledOccurrence) { skipped.append(occurrence) }
        func acknowledge(requestID: UUID) { acknowledged.append(requestID) }
        var retries = 0
        func retryPending() { retries += 1 }
        func onChange(_ handler: @escaping @MainActor () -> Void) { handlers.append(handler) }

        func set(_ state: WatchScheduledState) {
            current = state
            for handler in handlers {
                handler()
            }
        }
    }

    static let today = CalendarDay(year: 2026, month: 10, day: 20)
    static let streamBox = UUID(uuidString: "3B000000-0000-4000-8000-000000000001")!
    static let rent = UUID(uuidString: "3B000000-0000-4000-8000-000000000002")!
    static let gym = UUID(uuidString: "3B000000-0000-4000-8000-000000000003")!

    static let rows: [WatchScheduledOccurrence] = [
        WatchScheduledOccurrence(
            itemID: gym,
            day: CalendarDay(year: 2026, month: 10, day: 15),
            status: .overdue,
            type: .expense,
            amount: 1_500,
            currencyCode: "INR",
            details: "Gym",
            payeeName: "FitOrbit",
            categoryName: "Health",
            accountName: "Everyday Savings",
        ),
        WatchScheduledOccurrence(
            itemID: streamBox,
            day: today,
            status: .dueToday,
            type: .expense,
            amount: Decimal(string: "649.00")!,
            currencyCode: "INR",
            payeeName: "StreamBox",
            categoryName: "Entertainment",
            accountName: "Everyday Savings",
        ),
        WatchScheduledOccurrence(
            itemID: rent,
            day: CalendarDay(year: 2026, month: 11, day: 1),
            status: .upcoming,
            type: .expense,
            amount: 18_000,
            currencyCode: "INR",
            details: "Rent",
            categoryName: "Housing",
            accountName: "Everyday Savings",
        ),
    ]

    let fake = FakeWatchScheduled()

    func model() -> WatchScheduledViewModel {
        WatchScheduledViewModel(useCases: fake, locale: Locale(identifier: "en_IN"))
    }

    func sent(_ action: WatchScheduledRequest.Action, _ row: Int, result: WatchRequestResult? = nil)
        -> WatchSentRequest
    {
        let occurrence = Self.rows[row]
        return WatchSentRequest(
            request: WatchScheduledRequest(
                action: action,
                itemID: occurrence.itemID,
                occurrence: occurrence.day,
                tappedOn: Self.today,
            ),
            occurrence: occurrence,
            result: result,
        )
    }

    @Test("Before the first snapshot: Not Synced Yet; after an empty one, the normal empty state (6406964245)")
    func waitingForIPhone() {
        let model = model()
        #expect(model.isWaitingForIPhone && model.isEmpty)
        #expect(model.notSyncedTitle == "Not Synced Yet")
        #expect(model.notSyncedMessage == "Open little-orbit on your iPhone.")
        #expect(model.title == "Scheduled")
        fake.set(WatchScheduledState(snapshot: WatchSnapshot(today: Self.today)))
        #expect(!model.isWaitingForIPhone && model.isEmpty)
        #expect(model.emptyTitle == "Nothing Scheduled")
    }

    @Test("Opening or returning to the watch app retries what isn’t delivered yet (D377)")
    func appActiveRetries() {
        let model = model()
        model.appBecameActive()
        #expect(fake.retries == 1)
    }

    @Test("Rows: overdue, Today, then the next date, named as on the iPhone (Watch Scheduled list frame)")
    func rows() throws {
        fake.current = WatchScheduledState(snapshot: WatchSnapshot(today: Self.today, scheduled: Self.rows))
        let model = model()
        #expect(!model.isWaitingForIPhone)
        #expect(model.rows.map(\.title) == ["Gym · FitOrbit", "StreamBox", "Rent"])
        #expect(model.rows[0].dateText == "Overdue · 15 Oct" && model.rows[0].isOverdue)
        #expect(model.rows[1].dateText == "Today")
        #expect(model.rows[2].dateText.contains("Sun") && model.rows[2].dateText.contains("1 Nov"))
        #expect(model.rows.allSatisfy { $0.symbolName == "calendar" && !$0.isPending })
        #expect(model.rows[1].amount.contains("649.00") && !model.rows[1].amount.contains("-"))
        // The Pay screen's line (Watch Pay frame).
        #expect(model.rows[1].detail == "Due today · Everyday Savings · Entertainment")
        #expect(model.payTitle == "Pay" && model.skipTitle == "Skip")
        #expect(model.rows.map(\.id) == Self.rows.map(\.id))
    }

    @Test("Pay and Skip go to the use case; a syncing row reads Paid · syncing and can’t be tapped again")
    func paySkipAndSyncing() throws {
        fake.current = WatchScheduledState(snapshot: WatchSnapshot(today: Self.today, scheduled: Self.rows))
        let model = model()
        model.pay(Self.rows[1].id)
        model.skip(Self.rows[0].id)
        #expect(fake.paid == [Self.rows[1]] && fake.skipped == [Self.rows[0]])
        fake.set(WatchScheduledState(snapshot: fake.current.snapshot, sent: [sent(.pay, 1), sent(.skip, 0)]))
        #expect(model.rows[1].dateText == "Paid · syncing" && model.rows[1].isPending)
        #expect(model.rows[1].symbolName == "clock")
        #expect(model.rows[0].dateText == "Skipped · syncing")
        model.pay(Self.rows[1].id)
        #expect(fake.paid.count == 1)
    }

    @Test(
        "D343: the title says what happened on the iPhone; the message follows the action tapped on the watch",
        arguments: [
            (WatchRequestResult.alreadyPaid, "Already paid on iPhone"),
            (.alreadySkipped, "Already skipped on iPhone"),
            (.deleted, "Deleted on iPhone"),
        ],
    )
    func conflictMessages(_ result: WatchRequestResult, _ title: String) throws {
        fake.current = WatchScheduledState(
            snapshot: WatchSnapshot(today: Self.today, scheduled: Self.rows),
            sent: [sent(.pay, 1, result: result)],
        )
        let model = model()
        let pay = try #require(model.conflict)
        #expect(pay.title == title)
        #expect(
            pay.message
                == "StreamBox · 20 Oct. Your Pay from the watch wasn’t recorded, and Everyday Savings is unchanged."
        )
        // No amount in either message (S19).
        #expect(!pay.message.contains("649"))
        fake.set(WatchScheduledState(snapshot: fake.current.snapshot, sent: [sent(.skip, 0, result: result)]))
        let skip = try #require(model.conflict)
        #expect(skip.title == title)
        #expect(skip.message == "Gym · FitOrbit · 15 Oct. Your Skip from the watch wasn’t applied.")
        model.closeConflict()
        #expect(fake.acknowledged == [skip.id])
    }

    @Test("A pending request shows no message; one message at a time, oldest first")
    func oneConflictAtATime() throws {
        let first = sent(.pay, 1, result: .alreadySkipped)
        fake.current = WatchScheduledState(
            snapshot: WatchSnapshot(today: Self.today, scheduled: Self.rows),
            sent: [sent(.pay, 2), first, sent(.skip, 0, result: .deleted)],
        )
        let model = model()
        #expect(model.conflict?.id == first.id)
        fake.set(WatchScheduledState(snapshot: fake.current.snapshot, sent: [sent(.pay, 2)]))
        #expect(model.conflict == nil)
    }
}

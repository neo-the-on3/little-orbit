import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// S85: an account's history shows its scheduled occurrences as Upcoming rows, tagged Scheduled, that open their
/// item and can't be edited or deleted as transactions.
@MainActor
@Suite("Scheduled occurrences in account history (S85, #197)")
struct AccountHistoryScheduledTests {
    private func history(_ scene: ScheduledScene) -> AccountHistoryViewModel {
        let useCases = TransactionUseCases(repository: scene.repository, categoryNames: CatalogDefaultCategoryNames())
            .showingScheduled(from: scene.repository)
        return AccountHistoryViewModel(
            useCases: useCases,
            accountID: scene.account.id,
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: ScheduledScene.zone)!,
            now: { [scene] in scene.now },
        )
    }

    @Test("A scheduled occurrence is an Upcoming row with a projected balance, its item and the Scheduled tag")
    func scheduledRow() throws {
        let scene = try ScheduledScene()
        let gym = scene.item("Gym", day: 25, month: 10)
        try scene.add(gym)
        let entered = Transaction(
            type: .expense,
            amount: 300,
            date: ScheduledScene.date(CalendarDay(year: 2026, month: 10, day: 22)),
            timeZoneID: ScheduledScene.zone,
            accountID: scene.account.id,
            details: "Dinner",
        )
        try scene.repository.saveTransaction(entered)
        let history = history(scene)
        history.load()
        #expect(history.balanceText == "₹1,00,000.00")
        // Newest first: 25 Oct (scheduled), then 22 Oct (entered); the next month's Gym is past the month ahead.
        let rows = history.upcoming
        #expect(rows.count == 2)
        let scheduled = try #require(rows.first)
        #expect(scheduled.isUpcoming)
        #expect(scheduled.scheduledItemID == gym.id)
        #expect(scheduled.balanceText == "Projected ₹98,500.00")
        #expect(scheduled.accessibilityLabel.contains("Scheduled"))
        #expect(rows.last?.isScheduled == false)
        #expect(history.scheduledItemID(of: scheduled.id) == gym.id)
        #expect(history.afterUpcomingText == "After upcoming: ₹98,500.00")
    }

    @Test("A scheduled row isn't deleted or edited as a transaction")
    func notStored() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 25, month: 10))
        let history = history(scene)
        history.load()
        let row = try #require(history.upcoming.first)
        #expect(history.storedIDs([row.id]).isEmpty)
        #expect(history.requestDelete(ids: [row.id]) == nil)
        #expect(history.deletePrompt == nil)
        history.load()
        #expect(history.upcoming.count == 1)
    }

    @Test("Without the schedule the history is as before")
    func withoutSchedule() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 25, month: 10))
        let history = AccountHistoryViewModel(
            useCases: TransactionUseCases(repository: scene.repository, categoryNames: CatalogDefaultCategoryNames()),
            accountID: scene.account.id,
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: ScheduledScene.zone)!,
            now: { [scene] in scene.now },
        )
        history.load()
        #expect(history.upcoming.isEmpty)
    }
}

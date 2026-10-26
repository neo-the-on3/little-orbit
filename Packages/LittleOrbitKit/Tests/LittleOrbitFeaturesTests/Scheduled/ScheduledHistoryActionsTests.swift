import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// What a scheduled history row's item sheet can do (D350.2), and Delete on a selection that includes scheduled
/// rows (Tech Architect, #203 NB 7).
@MainActor
@Suite("Scheduled history row actions (D350.2, #197)")
struct ScheduledHistoryActionsTests {
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

    @Test("The item's next occurrence offers Pay and Skip on that occurrence; a later one offers neither")
    func nextOccurrenceOnly() throws {
        let scene = try ScheduledScene()
        let gym = scene.item("Gym", day: 25, month: 10)
        try scene.add(gym, scene.item("Rent", day: 1, month: 9))
        let history = history(scene)
        history.load()
        let row = try #require(history.upcoming.first { $0.scheduledItemID == gym.id })
        let day = try #require(history.scheduledOccurrence(of: row.id))
        #expect(day == CalendarDay(year: 2026, month: 10, day: 25))

        let list = scene.feature().makeList()
        list.load()
        let rows = list.settleableRows(of: gym.id, .historyRow(day))
        #expect(rows.map(\.occurrence) == [day])
        #expect(list.settleableRows(of: gym.id, .historyRow(CalendarDay(year: 2026, month: 11, day: 25))).isEmpty)
        list.payNow(try #require(rows.first))
        #expect(scene.recorded.count == 1)
    }

    @Test("A history row of an item with an overdue occurrence isn't its next one, so it offers neither")
    func overdueFirst() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 18, month: 10)
        try scene.add(rent)
        let list = scene.feature().makeList()
        list.load()
        #expect(list.settleableRows(of: rent.id, .dueOccurrences).count == 1)
        #expect(list.settleableRows(of: rent.id, .historyRow(CalendarDay(year: 2026, month: 11, day: 18))).isEmpty)
    }

    @Test("NB 7: Delete on one stored and one scheduled row asks first, and the summary counts stored rows")
    func mixedDelete() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 25, month: 10))
        try scene.repository.saveTransaction(
            Transaction(
                type: .expense,
                amount: 300,
                date: ScheduledScene.date(CalendarDay(year: 2026, month: 10, day: 22)),
                timeZoneID: ScheduledScene.zone,
                accountID: scene.account.id,
                details: "Dinner",
            )
        )
        let history = history(scene)
        history.load()
        let ids = Set(history.upcoming.map(\.id))
        history.selection = ids
        #expect(history.selectionSummary == "1 selected")
        #expect(history.requestDelete(ids: ids) == nil)
        let prompt = try #require(history.deletePrompt)
        #expect(prompt.title == "Delete Transaction?")
        #expect(prompt.confirmTitle == "Delete Transaction")
        #expect(prompt.ids.count == 1)
        #expect(history.upcoming.count == 2)
    }
}

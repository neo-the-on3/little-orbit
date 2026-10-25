import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D348: Settings › Scheduled Items › Show upcoming, an On/Off switch, On by default. Off takes the scheduled
/// Upcoming rows out of account history; entered future transactions still show.
@MainActor
@Suite("Show upcoming (D348)")
struct ShowUpcomingSettingTests {
    private func history(_ scene: ScheduledScene, setting: any ShowUpcomingSettingStore) -> AccountHistoryViewModel {
        let useCases = TransactionUseCases(repository: scene.repository, categoryNames: CatalogDefaultCategoryNames())
            .showingScheduled(from: scene.repository, while: { setting.showsUpcoming })
        return AccountHistoryViewModel(
            useCases: useCases,
            accountID: scene.account.id,
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: ScheduledScene.zone)!,
            now: { [scene] in scene.now },
        )
    }

    @Test("On by default; Off hides scheduled rows and keeps entered ones; On again shows them")
    func toggles() throws {
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
        let store = InMemoryShowUpcomingSetting()
        let model = ScheduledUpcomingSettingsModel(store: store, updates: scene.updates)
        #expect(model.showsUpcoming)
        #expect(model.sectionTitle == "Scheduled Items")
        #expect(model.toggleTitle == "Show upcoming")
        let history = history(scene, setting: store)
        history.load()
        #expect(history.upcoming.count == 2)

        let revision = scene.updates.revision
        model.showsUpcoming = false
        #expect(!store.showsUpcoming)
        #expect(scene.updates.revision == revision + 1)
        history.load()
        #expect(history.upcoming.map(\.isScheduled) == [false])

        model.showsUpcoming = true
        history.load()
        #expect(history.upcoming.count == 2)
    }

    @Test("NB 5: a schedule that can't be read leaves the stored rows")
    func unreadableSchedule() throws {
        let scene = try ScheduledScene()
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
        let useCases = DefaultAccountHistoryUseCase(repository: scene.repository, schedule: UnreadableSchedule())
        let page = try #require(
            try useCases.history(of: scene.account.id, today: CalendarDay(year: 2026, month: 10, day: 20))
        )
        #expect(page.history.upcoming.count == 1)
    }
}

/// A schedule whose reads fail.
@MainActor
private final class UnreadableSchedule: ScheduleRepository {
    struct Failure: Error {}

    func scheduleLedger() throws -> LedgerSnapshot { throw Failure() }
    func saveScheduledItem(_: ScheduledItem, today _: CalendarDay, now _: Date) throws { throw Failure() }
    func saveScheduledItem(_: ScheduledItem, payee _: ScheduledPendingPayee?, today _: CalendarDay, now _: Date) throws
        -> ScheduledItemSaveChange
    { throw Failure() }
    func updateScheduledItem(_: ScheduledItem, payee _: ScheduledPendingPayee?, today _: CalendarDay, now _: Date)
        throws
        -> ScheduledItemSaveChange
    { throw Failure() }
    func revertScheduledItemSave(_: ScheduledItemSaveChange, undone _: Bool) throws -> ScheduledItemSaveRevert {
        throw Failure()
    }
    func updateScheduledOccurrence(
        _: ScheduledItem,
        editing _: ScheduledOccurrenceSave,
        payee _: ScheduledPendingPayee?,
        today _: CalendarDay,
        now _: Date,
    ) throws -> ScheduledItemSaveChange {
        throw Failure()
    }
    func deleteScheduledItem(id _: UUID) throws { throw Failure() }
    func settleScheduledOccurrence(_: ScheduledSettlement) throws -> ScheduledSettlementChange? { throw Failure() }
    func unsettleScheduledOccurrence(_: ScheduledSettlementChange) throws -> ScheduledSettlementRevert {
        throw Failure()
    }
    func resettleScheduledOccurrence(_: ScheduledSettlementChange) throws -> ScheduledSettlementRevert {
        throw Failure()
    }
    func catchUpScheduledItems(today _: CalendarDay, pruningOrphans _: Bool) throws -> ScheduledCatchUp {
        throw Failure()
    }
}

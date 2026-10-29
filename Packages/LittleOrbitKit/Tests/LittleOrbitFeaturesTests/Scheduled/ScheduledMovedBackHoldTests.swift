import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D447, through the list: while the removed-occurrences notice says an automatic item's payment is back on its
/// scheduled day, catch-up records nothing for the item. Undo then puts the move back with no record; OK records the
/// payment as usual, once. Made-up data in `Asia/Kolkata`, as Product Manager's gate check (G): Water Bill, ₹600.00
/// weekly on Mondays from Mon 26 Oct 2026, recorded automatically from Everyday Savings (INR), created on Sat 24 Oct,
/// when Mon 26 Oct is moved to Tue 3 Nov for this occurrence only. On Wed 28 Oct the form sets the End date to 31 Oct.
@MainActor
@Suite("Scheduled notice: catch-up waits for a payment moved back to its day (D447)")
struct ScheduledMovedBackHoldTests {
    private static func day(_ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: month, day: day)
    }

    private static let key = day(10, 26)
    private static let movedTo = day(11, 3)

    private struct Opened {
        let scene: ScheduledScene
        let feature: ScheduledFeature
        let window: TestWindow
        let id: UUID
    }

    /// The scene on 28 Oct, with nothing recorded yet: 26 Oct is due on 3 Nov.
    private func scene() throws -> Opened {
        let scene = try ScheduledScene(today: Self.day(10, 24))
        let water = ScheduledItem(
            amount: 600,
            accountID: scene.account.id,
            categoryID: scene.housing.id,
            details: "Water Bill",
            startDay: Self.day(10, 26),
            repeatRule: .weekly,
            processesAutomatically: true,
            timeZoneID: ScheduledScene.zone,
            createdAt: scene.now,
        )
        try scene.repository.saveScheduledItem(water, today: Self.day(10, 24), now: scene.now)
        let item = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        _ = try scene.repository.updateScheduledOccurrence(
            item,
            editing: ScheduledOccurrenceSave(occurrence: Self.key, dueDay: Self.movedTo, scope: .thisOccurrence),
            payee: nil,
            today: Self.day(10, 24),
            now: scene.now,
        )
        scene.now = ScheduledScene.date(Self.day(10, 28))
        let useCases = TransactionUseCases(
            repository: scene.repository,
            categoryNames: CatalogDefaultCategoryNames(),
            schedule: scene.repository,
        )
        let feature = scene.feature()
        #expect(feature.catchUp(atLaunch: false)?.posted.isEmpty == true)
        return Opened(
            scene: scene,
            feature: feature,
            window: TestWindow(useCases, updates: scene.updates),
            id: water.id,
        )
    }

    /// A list in the window, after the form's End date save on 28 Oct, showing the notice.
    private func savedEnd(_ opened: Opened) throws -> ScheduledListViewModel {
        let list = opened.feature.makeList()
        list.useUndoHistory(opened.window.history)
        list.load()
        list.openEditor(opened.id)
        let form = try #require(list.form)
        form.hasEnd = true
        form.endDay = Self.day(10, 31)
        #expect(form.save())
        #expect(
            list.removedNotice?.message
                == "A moved payment was due after the new end date, so it’s back on its scheduled day: 26 Oct."
        )
        return list
    }

    private func stored(_ opened: Opened) throws -> ScheduledItem {
        try #require(try opened.scene.repository.scheduleLedger().scheduledItems.first)
    }

    private func recorded(_ opened: Opened) throws -> [Transaction] {
        try opened.scene.repository.transactions().filter { $0.scheduledTemplateID != nil }
    }

    @Test("While the notice shows, an activation catch-up records nothing; OK then records 26 Oct once, ₹600.00")
    func okRecordsOnce() throws {
        let opened = try scene()
        let list = try savedEnd(opened)
        #expect(opened.feature.catchUp(atLaunch: false)?.posted.isEmpty == true)
        #expect(try stored(opened).occurrence(on: Self.key) == nil)
        list.dismissRemovedNotice()
        #expect(list.removedNotice == nil)
        #expect(try stored(opened).occurrence(on: Self.key)?.outcome == .posted)
        #expect(try recorded(opened).map(\.amount) == [600])
        // From Everyday Savings, dated 26 Oct: its only change, so its balance is lower by exactly ₹600.00.
        #expect(try recorded(opened).map(\.accountID) == [opened.scene.account.id])
        #expect(opened.feature.catchUp(atLaunch: false)?.posted.isEmpty == true)
        #expect(try recorded(opened).count == 1)
    }

    @Test("While the notice shows, catch-up records nothing; its Undo restores the move with no record, due 3 Nov")
    func undoRestoresTheMove() throws {
        let opened = try scene()
        let list = try savedEnd(opened)
        #expect(opened.feature.catchUp(atLaunch: false)?.posted.isEmpty == true)
        list.undoRemovedNotice()
        #expect(list.removedNotice == nil)
        let item = try stored(opened)
        #expect(item.endDay == nil)
        #expect(item.occurrence(on: Self.key)?.outcome == .edited)
        #expect(item.dueDay(of: Self.key) == Self.movedTo)
        #expect(opened.feature.catchUp(atLaunch: false)?.posted.isEmpty == true)
        #expect(try recorded(opened).isEmpty)
        // Undo ended the hold: on 3 Nov catch-up records the move as usual, while the list is still open, with
        // Mon 2 Nov, since there's no End date again.
        opened.scene.now = ScheduledScene.date(Self.movedTo)
        #expect(opened.feature.catchUp(atLaunch: false)?.posted.count == 2)
        #expect(try stored(opened).occurrence(on: Self.key)?.outcome == .posted)
        #expect(list.removedNotice == nil)
    }

    @Test("When the alert closes the notice before its button acts, OK still records and Undo still restores")
    func buttonsActOnTheNoticeTheyWereShownWith() throws {
        let opened = try scene()
        let list = try savedEnd(opened)
        let notice = try #require(list.removedNotice)
        list.removedNoticeClosed()
        list.undoRemovedNotice(notice)
        #expect(try stored(opened).dueDay(of: Self.key) == Self.movedTo)
        #expect(try recorded(opened).isEmpty)

        let again = try scene()
        let second = try savedEnd(again)
        let shown = try #require(second.removedNotice)
        second.removedNoticeClosed()
        second.dismissRemovedNotice(shown)
        #expect(try recorded(again).map(\.amount) == [600])
    }

    @Test("A new launch has no notice showing, so its launch catch-up records 26 Oct once")
    func newLaunchRecords() throws {
        let opened = try scene()
        let list = try savedEnd(opened)
        #expect(opened.feature.catchUp(atLaunch: false)?.posted.isEmpty == true)
        // The App's launch catch-up runs on a new feature, with its own holds, as a new process does.
        #expect(opened.scene.feature().catchUp(atLaunch: true)?.posted.map(\.amount) == [600])
        #expect(opened.feature.catchUp(atLaunch: false)?.posted.isEmpty == true)
        #expect(try recorded(opened).count == 1)
        #expect(list.removedNotice != nil)
    }

    @Test("A hold ends when its list goes away, so the next catch-up records 26 Oct once")
    func holdEndsWithItsList() throws {
        let opened = try scene()
        weak var gone: ScheduledListViewModel?
        do {
            let list = try savedEnd(opened)
            gone = list
            #expect(opened.feature.catchUp(atLaunch: false)?.posted.isEmpty == true)
        }
        #expect(gone == nil)
        #expect(opened.feature.catchUp(atLaunch: false)?.posted.count == 1)
        #expect(try recorded(opened).count == 1)
    }
}

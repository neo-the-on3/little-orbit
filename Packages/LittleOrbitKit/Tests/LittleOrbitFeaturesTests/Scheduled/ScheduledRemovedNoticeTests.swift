import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D442.3: a form save that removes occurrences the new schedule has no place for shows one notice naming them, and
/// Edit › Undo of the save puts them back. Made-up data in `Asia/Kolkata`: Phone Plan, ₹199.00 weekly on Mondays from
/// Mon 12 Oct 2026, from Everyday Savings (INR). On Tue 20 Oct occurrences are edited for this occurrence only; on
/// Wed 21 Oct the form saves the item.
@MainActor
@Suite("Scheduled form save: the notice for removed occurrences (D442.3)")
struct ScheduledRemovedNoticeTests {
    private static func day(_ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: month, day: day)
    }

    /// One "This occurrence only" edit on 20 Oct: `key` moved to `movedTo`, or given its own `amount`.
    private struct Edit {
        var key: CalendarDay
        var movedTo: CalendarDay?
        var amount: Decimal?
    }

    /// The scene, kept alive for its use cases, with a list in a window whose Undo steps the list records.
    private struct Opened {
        let scene: ScheduledScene
        let list: ScheduledListViewModel
        let window: TestWindow
        let id: UUID
    }

    /// The list on 21 Oct, after `edits` on 20 Oct.
    private func window(_ edits: [Edit]) throws -> Opened {
        let scene = try ScheduledScene()
        let phone = ScheduledItem(
            amount: 199,
            accountID: scene.account.id,
            categoryID: scene.housing.id,
            details: "Phone Plan",
            startDay: Self.day(10, 12),
            repeatRule: .weekly,
            timeZoneID: ScheduledScene.zone,
            createdAt: scene.now,
        )
        try scene.repository.saveScheduledItem(phone, today: Self.day(10, 20), now: scene.now)
        for edit in edits {
            var item = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
            if let amount = edit.amount {
                item.amount = amount
            }
            let save = ScheduledOccurrenceSave(
                occurrence: edit.key,
                dueDay: edit.movedTo ?? edit.key,
                scope: .thisOccurrence,
            )
            _ = try scene.repository.updateScheduledOccurrence(
                item,
                editing: save,
                payee: nil,
                today: Self.day(10, 20),
                now: scene.now,
            )
        }
        scene.now = ScheduledScene.date(Self.day(10, 21))
        let useCases = TransactionUseCases(
            repository: scene.repository,
            categoryNames: CatalogDefaultCategoryNames(),
            schedule: scene.repository,
        )
        let window = TestWindow(useCases, updates: scene.updates)
        let list = scene.feature().makeList()
        list.recordStep = { [history = window.history] change, name, subject in
            history.record(change, named: name, subject: subject)
        }
        list.load()
        return Opened(scene: scene, list: list, window: window, id: phone.id)
    }

    private func stored(_ scene: ScheduledScene) throws -> ScheduledItem {
        try #require(try scene.repository.scheduleLedger().scheduledItems.first)
    }

    @Test("D442 (A): End 31 Oct with 2 Nov moved to Fri 23 Oct removes nothing and shows no notice")
    func noNoticeWhenNothingIsRemoved() throws {
        let opened = try window([Edit(key: Self.day(11, 2), movedTo: Self.day(10, 23))])
        let (scene, list, id) = (opened.scene, opened.list, opened.id)
        list.openEditor(id)
        let form = try #require(list.form)
        form.hasEnd = true
        form.endDay = Self.day(10, 31)
        #expect(form.save())
        #expect(list.alert == nil)
        #expect(try stored(scene).dueDay(of: Self.day(11, 2)) == Self.day(10, 23))
    }

    @Test("D442 (B): End 31 Oct with 26 Oct moved to Tue 3 Nov shows the notice; Undo restores 3 Nov and no End")
    func movedAfterTheEndNoticeAndUndo() throws {
        let opened = try window([Edit(key: Self.day(10, 26), movedTo: Self.day(11, 3))])
        let (scene, list, window, id) = (opened.scene, opened.list, opened.window, opened.id)
        list.openEditor(id)
        let form = try #require(list.form)
        form.hasEnd = true
        form.endDay = Self.day(10, 31)
        #expect(form.save())
        #expect(list.alert?.title == "1 moved payment after the end date was removed: 3 Nov")
        #expect(try stored(scene).occurrence(on: Self.day(10, 26)) == nil)
        #expect(window.undoManager.undoActionName == "Edit Phone Plan")
        window.history.undo()
        let item = try stored(scene)
        #expect(item.endDay == nil)
        #expect(item.occurrence(on: Self.day(10, 26))?.outcome == .edited)
        #expect(item.dueDay(of: Self.day(10, 26)) == Self.day(11, 3))
    }

    @Test("D442 (C): Starts Tue 27 Oct with 26 Oct at ₹249.00 shows the notice; Undo restores ₹249.00 and Starts")
    func editedOffTheScheduleNoticeAndUndo() throws {
        let opened = try window([Edit(key: Self.day(10, 26), amount: 249)])
        let (scene, list, window, id) = (opened.scene, opened.list, opened.window, opened.id)
        list.openEditor(id)
        let form = try #require(list.form)
        form.startDay = Self.day(10, 27)
        #expect(form.save())
        #expect(
            list.alert?.title == "1 edited occurrence no longer matches the schedule and was removed: 26 Oct"
        )
        #expect(try stored(scene).occurrence(on: Self.day(10, 26)) == nil)
        window.history.undo()
        let item = try stored(scene)
        #expect(item.startDay == Self.day(10, 12))
        #expect(item.occurrence(on: Self.day(10, 26))?.edit?.amount == 249)
        #expect(item.resolved(for: Self.day(10, 26)).amount == 249)
    }

    @Test("D442.3: two moves past the new End are one notice with the plural and both dates")
    func twoRemovedMovesAreOneNotice() throws {
        let opened = try window([
            Edit(key: Self.day(10, 26), movedTo: Self.day(11, 3)),
            Edit(key: Self.day(11, 2), movedTo: Self.day(11, 10)),
        ])
        let (scene, list, id) = (opened.scene, opened.list, opened.id)
        list.openEditor(id)
        let form = try #require(list.form)
        form.hasEnd = true
        form.endDay = Self.day(10, 31)
        #expect(form.save())
        #expect(list.alert?.title == "2 moved payments after the end date were removed: 3 Nov and 10 Nov")
        #expect(try stored(scene).occurrences.allSatisfy { $0.edit == nil })
    }
}

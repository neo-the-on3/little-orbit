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
        list.useUndoHistory(window.history)
        list.load()
        return Opened(scene: scene, list: list, window: window, id: phone.id)
    }

    private func stored(_ scene: ScheduledScene) throws -> ScheduledItem {
        try #require(try scene.repository.scheduleLedger().scheduledItems.first)
    }

    /// The form's save on 21 Oct, `change` made in it.
    private func save(_ opened: Opened, _ change: (ScheduledFormViewModel) -> Void) throws {
        opened.list.openEditor(opened.id)
        let form = try #require(opened.list.form)
        change(form)
        #expect(form.save())
    }

    private func end(_ day: CalendarDay) -> (ScheduledFormViewModel) -> Void {
        { form in
            form.hasEnd = true
            form.endDay = day
        }
    }

    @Test("D442 (A): End 31 Oct with 2 Nov moved to Fri 23 Oct removes nothing and shows no notice")
    func noNoticeWhenNothingIsRemoved() throws {
        let opened = try window([Edit(key: Self.day(11, 2), movedTo: Self.day(10, 23))])
        try save(opened, end(Self.day(10, 31)))
        #expect(opened.list.removedNotice == nil)
        #expect(opened.list.alert == nil)
        #expect(try stored(opened.scene).dueDay(of: Self.day(11, 2)) == Self.day(10, 23))
    }

    @Test("D444.1 (B): End 31 Oct with 26 Oct moved to Tue 3 Nov: back on 26 Oct; Edit › Undo restores 3 Nov, no End")
    func movedBackNoticeAndEditUndo() throws {
        let opened = try window([Edit(key: Self.day(10, 26), movedTo: Self.day(11, 3))])
        try save(opened, end(Self.day(10, 31)))
        #expect(
            opened.list.removedNotice?.message
                == "A moved payment was due after the new end date, so it’s back on its scheduled day: 26 Oct."
        )
        #expect(try stored(opened.scene).occurrence(on: Self.day(10, 26)) == nil)
        #expect(opened.window.undoManager.undoActionName == "Edit Phone Plan")
        opened.window.history.undo()
        let item = try stored(opened.scene)
        #expect(item.endDay == nil)
        #expect(item.occurrence(on: Self.day(10, 26))?.outcome == .edited)
        #expect(item.dueDay(of: Self.day(10, 26)) == Self.day(11, 3))
    }

    @Test("D442 (C): Starts Tue 27 Oct with 26 Oct at ₹249.00 shows the notice; Undo restores ₹249.00 and Starts")
    func editedOffTheScheduleNoticeAndUndo() throws {
        let opened = try window([Edit(key: Self.day(10, 26), amount: 249)])
        try save(opened) { $0.startDay = Self.day(10, 27) }
        #expect(
            opened.list.removedNotice?.message
                == "An edited payment no longer matches the schedule and was removed: 26 Oct."
        )
        #expect(try stored(opened.scene).occurrence(on: Self.day(10, 26)) == nil)
        opened.window.history.undo()
        let item = try stored(opened.scene)
        #expect(item.startDay == Self.day(10, 12))
        #expect(item.occurrence(on: Self.day(10, 26))?.edit?.amount == 249)
        #expect(item.resolved(for: Self.day(10, 26)).amount == 249)
    }

    @Test("D444.2 (D): End 31 Oct with ₹249.00 on Mon 2 Nov shows the edited-payment notice on 2 Nov")
    func editedPastTheEndNotice() throws {
        let opened = try window([Edit(key: Self.day(11, 2), amount: 249)])
        try save(opened, end(Self.day(10, 31)))
        #expect(
            opened.list.removedNotice?.message
                == "An edited payment no longer matches the schedule and was removed: 2 Nov."
        )
        #expect(try stored(opened.scene).occurrence(on: Self.day(11, 2)) == nil)
    }

    @Test("D444.1 (E): End 31 Oct with Mon 2 Nov moved to Tue 3 Nov shows the removed wording on 3 Nov")
    func movedRemovedNotice() throws {
        let opened = try window([Edit(key: Self.day(11, 2), movedTo: Self.day(11, 3))])
        try save(opened, end(Self.day(10, 31)))
        #expect(
            opened.list.removedNotice?.message
                == "A moved payment was due after the new end date and was removed: 3 Nov."
        )
        #expect(try stored(opened.scene).occurrence(on: Self.day(11, 2)) == nil)
    }

    @Test("D444 (F): the notice's Undo undoes the whole save as Edit › Undo does, and closes the notice")
    func noticeUndoButtonRestoresEverything() throws {
        let opened = try window([
            Edit(key: Self.day(10, 26), movedTo: Self.day(11, 3)), Edit(key: Self.day(11, 2), amount: 249),
        ])
        let before = try stored(opened.scene)
        try save(opened) { form in
            form.details = "Phone Plan (new)"
            form.hasEnd = true
            form.endDay = Self.day(10, 31)
        }
        #expect(opened.list.removedNotice != nil)
        #expect(opened.list.removedNoticeUndoTitle == "Undo")
        opened.list.undoRemovedNotice()
        #expect(opened.list.removedNotice == nil)
        let item = try stored(opened.scene)
        #expect(item.details == "Phone Plan")
        #expect(item.endDay == nil)
        #expect(item.occurrences == before.occurrences)
        #expect(item.dueDay(of: Self.day(10, 26)) == Self.day(11, 3))
        #expect(item.resolved(for: Self.day(11, 2)).amount == 249)
        // It was the window's own Undo step, so Redo now repeats the save.
        #expect(opened.window.undoManager.redoActionName == "Edit Phone Plan (new)")
    }

    @Test("D444 (F): OK closes the notice and keeps the save")
    func noticeOkKeepsTheSave() throws {
        let opened = try window([Edit(key: Self.day(10, 26), movedTo: Self.day(11, 3))])
        try save(opened, end(Self.day(10, 31)))
        opened.list.dismissRemovedNotice()
        #expect(opened.list.removedNotice == nil)
        #expect(try stored(opened.scene).endDay == Self.day(10, 31))
    }

    @Test("D444: one save with every case is one notice, one sentence each, with both plurals and the list format")
    func everyCaseIsOneNotice() throws {
        // End 7 Nov: 26 Oct and 2 Nov moved past it go back; Mon 9 Nov moved to Tue 10 Nov is removed; ₹249.00 on
        // Mon 16 Nov is removed.
        let opened = try window([
            Edit(key: Self.day(10, 26), movedTo: Self.day(11, 9)),
            Edit(key: Self.day(11, 2), movedTo: Self.day(11, 10)),
            Edit(key: Self.day(11, 9), movedTo: Self.day(11, 10)),
            Edit(key: Self.day(11, 16), amount: 249),
        ])
        try save(opened, end(Self.day(11, 7)))
        let lines = try #require(opened.list.removedNotice?.message).components(separatedBy: "\n")
        #expect(
            lines == [
                "2 moved payments were due after the new end date, so they’re back on their scheduled days: 26 Oct"
                    + " and 2 Nov.",
                "A moved payment was due after the new end date and was removed: 10 Nov.",
                "An edited payment no longer matches the schedule and was removed: 16 Nov.",
            ]
        )
    }
}

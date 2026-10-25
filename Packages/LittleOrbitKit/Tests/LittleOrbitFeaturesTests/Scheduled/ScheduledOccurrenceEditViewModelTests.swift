import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Occurrence edits on the Scheduled screens (#197 item 3; #26 D45, D59, D106, D114, D115). Made-up data.
@MainActor
private struct RentScene {
    let scene: ScheduledScene
    let list: ScheduledListViewModel
    let id: UUID
}

@MainActor
@Suite("Scheduled occurrence edits on the screens (#197)")
struct ScheduledOccurrenceEditViewModelTests {
    private let november = CalendarDay(year: 2026, month: 11, day: 1)

    /// A manual Rent of ₹1,200, monthly on the 1st from 1 Nov 2026; today is 20 Oct.
    private func scene(platform: ScheduledPlatform = .iOS) throws -> RentScene {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, month: 11)
        try scene.add(rent)
        let list = ScheduledListViewModel(
            useCases: scene.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: platform,
        )
        list.load()
        return RentScene(scene: scene, list: list, id: rent.id)
    }

    private func stored(_ id: UUID, _ scene: ScheduledScene) throws -> ScheduledItem {
        try #require(try scene.repository.scheduleLedger().scheduledItems.first { $0.id == id })
    }

    @Test("D45, D59: Edit on a row opens on its occurrence; an amount change asks, with the approved strings")
    func amountChangeAsks() throws {
        let rent = try scene()
        let (scene, list, id) = (rent.scene, rent.list, rent.id)
        let row = try #require(list.upcomingRows.first)
        #expect(row.editOccurrence == november)
        list.openEditor(row.itemID, occurrence: row.editOccurrence)
        let form = try #require(list.form)
        #expect(form.showsDueDate)
        #expect(form.dueDateLabel == "Due Date")
        form.amountText = "1300"
        #expect(form.save() == false)
        let question = try #require(form.scopeQuestion)
        #expect(question.title == "Save Changes to Rent?")
        #expect(question.message == "Change only the 1 Nov occurrence, or 1 Nov and every later one?")
        #expect(question.thisOccurrenceTitle == "This occurrence only")
        #expect(question.allFutureTitle == "All future occurrences")
        #expect(question.cancelTitle == "Cancel")
        #expect(try stored(id, scene).occurrences.isEmpty)
        #expect(form.save(scope: .thisOccurrence))
        #expect(form.isFinished)
        #expect(form.scopeQuestion == nil)
        let item = try stored(id, scene)
        #expect(item.amount == 1_200)
        #expect(item.resolved(for: november).amount == 1_300)
        #expect(list.upcomingRows.first?.amount.contains("1,300") == true)
    }

    @Test("D45: All future occurrences gives the item the new amount")
    func allFuture() throws {
        let rent = try scene()
        let (scene, list, id) = (rent.scene, rent.list, rent.id)
        list.openEditor(id, occurrence: november)
        let form = try #require(list.form)
        form.amountText = "1300"
        #expect(form.save() == false)
        #expect(form.save(scope: .allFuture))
        #expect(try stored(id, scene).amount == 1_300)
    }

    @Test("D114, S80, S82: a SERIES-only change saves without asking, on iOS and the Mac")
    func seriesOnlyDoesNotAsk() throws {
        for platform in [ScheduledPlatform.iOS, .macOS] {
            let rent = try scene(platform: platform)
            let (scene, list, id) = (rent.scene, rent.list, rent.id)
            list.openEditor(id, occurrence: november)
            let form = try #require(list.form)
            form.hasEnd = true
            form.endDay = CalendarDay(year: 2027, month: 6, day: 1)
            form.interval = 2
            #expect(form.save())
            #expect(form.scopeQuestion == nil)
            let item = try stored(id, scene)
            #expect(item.endDay == CalendarDay(year: 2027, month: 6, day: 1))
            #expect(item.repeatRule == .every(2, .month))
        }
    }

    @Test(
        "D115: a SERIES change with an amount change asks, and This occurrence only applies the end date to the series"
    )
    func mixedSave() throws {
        let rent = try scene(platform: .macOS)
        let (scene, list, id) = (rent.scene, rent.list, rent.id)
        list.openEditor(id, occurrence: november)
        let form = try #require(list.form)
        form.hasEnd = true
        form.endDay = CalendarDay(year: 2027, month: 6, day: 1)
        form.amountText = "1300"
        #expect(form.save() == false)
        #expect(form.scopeQuestion?.title == "Save Changes to Rent?")
        #expect(form.save(scope: .thisOccurrence))
        let item = try stored(id, scene)
        #expect(item.endDay == CalendarDay(year: 2027, month: 6, day: 1))
        #expect(item.amount == 1_200)
        #expect(item.resolved(for: november).amount == 1_300)
    }

    @Test("D45: a moved occurrence reads its new day on the row and keeps its own key for Edit, Pay and Skip")
    func movedOccurrenceRow() throws {
        let rent = try scene()
        let (scene, list, id) = (rent.scene, rent.list, rent.id)
        list.openEditor(id, occurrence: november)
        let form = try #require(list.form)
        form.dueDay = CalendarDay(year: 2026, month: 11, day: 3)
        #expect(form.save() == false)
        #expect(form.save(scope: .thisOccurrence))
        let row = try #require(list.upcomingRows.first)
        #expect(row.dateText == "3 Nov")
        #expect(row.editOccurrence == november)
        // Reopened, the form shows the occurrence's own day, and saving it unchanged doesn't ask.
        list.openEditor(id, occurrence: row.editOccurrence)
        let again = try #require(list.form)
        #expect(again.dueDay == CalendarDay(year: 2026, month: 11, day: 3))
        #expect(again.save())
        scene.now = ScheduledScene.date(CalendarDay(year: 2026, month: 11, day: 3))
        list.load()
        let due = try #require(list.dueTodayRows.first)
        #expect(due.occurrence == november)
        list.payNow(due)
        list.payNow(due)
        #expect(scene.recorded.count == 1)
        #expect(scene.recorded.first?.id == ScheduledKey.transactionID(item: id, day: november))
    }

    @Test("NB 6: with 1 Dec moved to 3 Jan, skipping 1 Nov names 1 Jan as the next due date")
    func skipAndEndedUseMovedDays() throws {
        let rent = try scene()
        let (scene, list, id) = (rent.scene, rent.list, rent.id)
        let december = CalendarDay(year: 2026, month: 12, day: 1)
        list.openEditor(id, occurrence: december)
        let form = try #require(list.form)
        form.dueDay = CalendarDay(year: 2027, month: 1, day: 3)
        #expect(form.save() == false)
        #expect(form.save(scope: .thisOccurrence))
        scene.now = ScheduledScene.date(CalendarDay(year: 2026, month: 11, day: 2))
        list.load()
        list.confirmSkip(try #require(list.overdueRows.first))
        let message = try #require(list.confirmation?.message)
        #expect(message.contains("1 Jan 2027"))
        #expect(!message.contains("1 Dec"))
    }

    @Test("D369 with moves: Next skips the overdue 1 Nov and the moved 1 Dec, and a move to today is Next")
    func nextUsesMovedDays() throws {
        let rent = try scene()
        let (scene, list, id) = (rent.scene, rent.list, rent.id)
        let december = CalendarDay(year: 2026, month: 12, day: 1)
        list.openEditor(id, occurrence: december)
        let form = try #require(list.form)
        form.dueDay = CalendarDay(year: 2027, month: 1, day: 3)
        #expect(form.save(scope: .thisOccurrence))
        scene.now = ScheduledScene.date(CalendarDay(year: 2026, month: 11, day: 2))
        list.load()
        let next = try #require(list.detail(id)?.next)
        #expect(next.contains("1 Jan"))
        #expect(!next.contains("Nov") && !next.contains("Dec"))

        list.openEditor(id, occurrence: december)
        let again = try #require(list.form)
        again.dueDay = CalendarDay(year: 2026, month: 11, day: 2)
        #expect(again.save(scope: .thisOccurrence))
        list.load()
        #expect(list.detail(id)?.next == "Next: 2 Nov")
    }

    @Test("The item screen's Edit opens on the first due occurrence, else the next one")
    func itemScreenOccurrence() throws {
        let rent = try scene()
        let (list, id) = (rent.list, rent.id)
        #expect(list.detail(id)?.editOccurrence == november)
    }

    @Test("D45: a one-off item has no Due Date row and saves without asking")
    func oneOffDoesNotAsk() throws {
        let scene = try ScheduledScene()
        var fee = scene.item("Locker Fee", day: 1, month: 11)
        fee.repeatRule = .never
        try scene.add(fee)
        let list = ScheduledListViewModel(
            useCases: scene.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: .iOS,
        )
        list.load()
        let row = try #require(list.upcomingRows.first)
        list.openEditor(row.itemID, occurrence: row.editOccurrence)
        let form = try #require(list.form)
        #expect(!form.showsDueDate)
        form.amountText = "900"
        #expect(form.save())
        #expect(try stored(fee.id, scene).amount == 900)
    }
}

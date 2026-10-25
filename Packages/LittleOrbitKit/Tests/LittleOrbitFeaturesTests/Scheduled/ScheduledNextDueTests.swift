import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// D369: the item screen's "Next:" is the next date on the current schedule that's today or later, never an
/// overdue one; overdue days keep their own rows (D339, D340). Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Scheduled item screen Next date (#26, D369)")
struct ScheduledNextDueTests {
    @Test("Starts moved from the 1st to the 5th with Sep and Oct unpaid: Next is 5 Nov, both stay overdue")
    func startsChangedWhileOverdue() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, month: 8)
        try scene.add(rent)
        let list = scene.feature().makeList()
        list.load()
        let august = CalendarDay(year: 2026, month: 8, day: 1)
        list.payNow(try #require(list.overdueRows.first { $0.occurrence == august }))
        var edited = try #require(scene.repository.scheduleLedger().scheduledItems.first { $0.id == rent.id })
        edited.startDay = CalendarDay(year: 2026, month: 8, day: 5)
        try scene.useCases.manage.save(edited)
        list.load()
        let detail = try #require(list.detail(rent.id))
        #expect(detail.next == "Next: 5 Nov")
        #expect(
            detail.due.map(\.occurrence) == [
                CalendarDay(year: 2026, month: 9, day: 1), CalendarDay(year: 2026, month: 10, day: 1),
            ]
        )
        #expect(detail.due.allSatisfy { !$0.detail.contains("last day") })
    }

    @Test("Starts moved from 15 Aug to 16 Aug every 2 months: the kept 15 Oct isn't Next and isn't a last day")
    func keptDayAfterStartsEdit() throws {
        let scene = try ScheduledScene()
        var electricity = scene.item("Electricity", day: 15, month: 8)
        electricity.repeatRule = .every(2, .month)
        try scene.add(electricity)
        let list = scene.feature().makeList()
        list.load()
        list.confirmSkip(try #require(list.overdueRows.first { $0.itemID == electricity.id }))
        list.confirm()
        var edited = try #require(scene.repository.scheduleLedger().scheduledItems.first { $0.id == electricity.id })
        edited.startDay = CalendarDay(year: 2026, month: 8, day: 16)
        try scene.useCases.manage.save(edited)
        list.load()
        let detail = try #require(list.detail(electricity.id))
        #expect(detail.next == "Next: 16 Dec")
        let kept = try #require(detail.due.first)
        #expect(kept.occurrence == CalendarDay(year: 2026, month: 10, day: 15))
        #expect(!kept.detail.contains("last day"))
    }

    @Test("With nothing overdue, Next is the next date; a date due today is Next until it's settled")
    func noOverdueRows() throws {
        let scene = try ScheduledScene()
        let gym = scene.item("Gym", day: 1, month: 11)
        let phone = scene.item("Phone", day: 20, month: 10)
        try scene.add(gym, phone)
        let list = scene.feature().makeList()
        list.load()
        #expect(list.detail(gym.id)?.next == "Next: 1 Nov")
        #expect(list.detail(gym.id)?.due.isEmpty == true)
        #expect(list.detail(phone.id)?.next == "Next: 20 Oct")
        list.payNow(try #require(list.dueTodayRows.first { $0.itemID == phone.id }))
        #expect(list.detail(phone.id)?.next == "Next: 20 Nov")
    }

    @Test("Everything left is overdue and nothing follows: it reads Ended, and the overdue rows stay")
    func allOverdueNoFutureDate() throws {
        let scene = try ScheduledScene()
        var gym = scene.item("Gym", day: 5, month: 8)
        gym.endDay = CalendarDay(year: 2026, month: 10, day: 5)
        try scene.add(gym)
        let list = scene.feature().makeList()
        list.load()
        let detail = try #require(list.detail(gym.id))
        #expect(detail.next == "Ended 5 Oct")
        #expect(detail.due.count == 3)
    }
}

import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// D369: Skip's message names the next date on the schedule, the first unpaid, unskipped occurrence from the later
/// of the day after the skipped one and today, never another overdue day. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Scheduled Skip names the next date on the schedule (#26, D369)")
struct ScheduledSkipNextTests {
    private func skipMessage(_ item: ScheduledItem, on day: CalendarDay, in scene: ScheduledScene) throws -> String? {
        let list = scene.feature().makeList()
        list.load()
        let row = try #require(
            (list.overdueRows + list.dueTodayRows).first { $0.itemID == item.id && $0.occurrence == day }
        )
        list.confirmSkip(row)
        return list.confirmation?.message
    }

    @Test("Skipping an overdue 1 Sep on 20 Oct names 1 Nov, not the overdue 1 Oct")
    func overdueSkipNamesNextOnSchedule() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, month: 9)
        try scene.add(rent)
        let message = try skipMessage(rent, on: CalendarDay(year: 2026, month: 9, day: 1), in: scene)
        #expect(message == "Nothing is recorded for 1 Sep. The next due date stays on the schedule: 1 Nov 2026.")
    }

    @Test("Skipping a date due today names the following occurrence")
    func dueTodaySkipNamesFollowing() throws {
        let scene = try ScheduledScene()
        let phone = scene.item("Phone", day: 20, month: 10)
        try scene.add(phone)
        let message = try skipMessage(phone, on: CalendarDay(year: 2026, month: 10, day: 20), in: scene)
        #expect(message == "Nothing is recorded for 20 Oct. The next due date stays on the schedule: 20 Nov 2026.")
    }

    @Test("An overdue skip with only overdue days after it says there are no due dates after it")
    func nothingAfter() throws {
        let scene = try ScheduledScene()
        var gym = scene.item("Gym", day: 5, month: 9)
        gym.endDay = CalendarDay(year: 2026, month: 10, day: 5)
        try scene.add(gym)
        let message = try skipMessage(gym, on: CalendarDay(year: 2026, month: 9, day: 5), in: scene)
        #expect(message == "Nothing is recorded for 5 Sep. There are no due dates after it.")
    }
}

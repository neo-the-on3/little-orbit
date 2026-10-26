import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// D373: the item screen's "Ended ‹date› · ‹N› overdue", and Skip's "‹N› more occurrences are still overdue.",
/// with counts of 0, 1 and several, on iOS and the Mac. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Scheduled overdue counts on Ended and Skip (#26, D373)")
struct ScheduledD373Tests {
    private func list(_ scene: ScheduledScene, _ platform: ScheduledPlatform) -> ScheduledListViewModel {
        let list = ScheduledListViewModel(
            useCases: scene.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: platform,
        )
        list.load()
        return list
    }

    private func day(_ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: month, day: day)
    }

    @Test(
        "Ended reads alone with nothing overdue, then with 1 overdue, then with 3 overdue",
        arguments: [ScheduledPlatform.iOS, .macOS],
    )
    func endedCounts(platform: ScheduledPlatform) throws {
        let scene = try ScheduledScene()
        var paid = scene.item("Paid", day: 5, month: 8)
        paid.endDay = day(10, 5)
        var once = scene.item("Once", day: 1, month: 10)
        once.repeatRule = .never
        var gym = scene.item("Gym", day: 5, month: 8)
        gym.endDay = day(10, 5)
        try scene.add(paid, once, gym)
        let setup = list(scene, platform)
        for row in setup.overdueRows where row.itemID == paid.id {
            setup.payNow(row)
        }
        let model = list(scene, platform)
        #expect(model.detail(paid.id)?.next == "Ended 5 Oct")
        #expect(model.detail(once.id)?.next == "Ended 1 Oct · 1 overdue")
        #expect(model.detail(gym.id)?.next == "Ended 5 Oct · 3 overdue")
    }

    @Test(
        "Skip adds nothing with no other overdue day, then 1 more, then 3 more",
        arguments: [ScheduledPlatform.iOS, .macOS],
    )
    func skipCounts(platform: ScheduledPlatform) throws {
        let scene = try ScheduledScene()
        let none = scene.item("None", day: 1, month: 10)
        let one = scene.item("One", day: 1, month: 9)
        let three = scene.item("Three", day: 1, month: 7)
        try scene.add(none, one, three)
        let model = list(scene, platform)
        func message(_ item: ScheduledItem, _ occurrence: CalendarDay) throws -> String? {
            model.confirmSkip(
                try #require(model.overdueRows.first { $0.itemID == item.id && $0.occurrence == occurrence })
            )
            return model.confirmation?.message
        }
        let next = "The next due date stays on the schedule: 1 Nov 2026."
        #expect(try message(none, day(10, 1)) == "Nothing is recorded for 1 Oct. \(next)")
        #expect(
            try message(one, day(9, 1)) == "Nothing is recorded for 1 Sep. \(next) 1 more occurrence is still overdue."
        )
        #expect(
            try message(three, day(8, 1))
                == "Nothing is recorded for 1 Aug. \(next) 3 more occurrences are still overdue."
        )
    }

    @Test("Skipping today's date counts every overdue one", arguments: [ScheduledPlatform.iOS, .macOS])
    func skipDueToday(platform: ScheduledPlatform) throws {
        let scene = try ScheduledScene()
        let phone = scene.item("Phone", day: 20, month: 8)
        try scene.add(phone)
        let model = list(scene, platform)
        model.confirmSkip(try #require(model.dueTodayRows.first { $0.itemID == phone.id }))
        #expect(
            model.confirmation?.message
                == "Nothing is recorded for 20 Oct. The next due date stays on the schedule: 20 Nov 2026. "
                + "2 more occurrences are still overdue."
        )
    }
}

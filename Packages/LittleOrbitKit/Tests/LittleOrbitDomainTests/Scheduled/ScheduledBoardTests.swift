import Foundation
import LittleOrbitDomain
import Testing

@MainActor
@Suite("Scheduled board and overdue count (#26, D106)")
struct ScheduledBoardTests {
    private typealias Fix = ScheduledFixture

    private func manual(_ name: String, day: Int) -> ScheduledItem {
        var item = Fix.rent(start: Fix.day(2026, 8, day), automatic: false)
        item.details = name
        return item
    }

    @Test("S76/S77: each missed manual occurrence is its own overdue row; today is due, not overdue")
    func overdueRows() throws {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let electricity = manual("Electricity", day: 15)
        let gym = manual("Gym", day: 18)
        let phone = manual("Phone Plan", day: 20)
        for item in [electricity, gym, phone] {
            try repository.useCases().save(item)
        }
        repository.now = Fix.date(2026, 10, 20)
        let useCases = repository.useCases()
        _ = try useCases.catchUp(atLaunch: true)
        var board = try useCases.listing().board
        #expect(board.overdue.count == 8)
        #expect(board.overdueCount == 8)
        #expect(board.dueToday.map(\.item.id) == [phone.id])
        #expect(board.upcoming.isEmpty)
        try useCases.payNow(itemID: gym.id, occurrence: Fix.day(2026, 8, 18))
        board = try useCases.listing().board
        #expect(board.overdueCount == 7)
    }

    @Test("Automatic items are recorded before the badge is read and never count")
    func automaticNeverCounts() throws {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        try repository.useCases().save(Fix.rent())
        try repository.useCases().save(manual("Electricity", day: 15))
        repository.now = Fix.date(2026, 10, 20)
        _ = try repository.useCases().catchUp(atLaunch: true)
        let board = try repository.useCases().listing().board
        #expect(board.overdueCount == 3)
        #expect(board.upcoming.count == 1)
    }

    @Test("S79: after the last occurrence is paid, the item is Completed, not Active")
    func completed() throws {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let item = Fix.transfer(start: Fix.day(2026, 11, 5), end: Fix.day(2027, 10, 5))
        try repository.useCases().save(item)
        repository.now = Fix.date(2027, 10, 5)
        let useCases = repository.useCases()
        for day in ScheduleCalendar.occurrences(of: item, through: Fix.day(2027, 10, 5)) {
            try useCases.payNow(itemID: item.id, occurrence: day)
        }
        let board = try useCases.listing().board
        #expect(board.completed.map(\.id) == [item.id])
        #expect(board.overdue.isEmpty && board.dueToday.isEmpty && board.upcoming.isEmpty)
        #expect(repository.posted(for: item.id).count == 12)
    }

    @Test("A one-off item paid moves to Completed")
    func oneOffCompleted() throws {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let item = Fix.rent(start: Fix.day(2026, 11, 1), rule: .never, automatic: false)
        try repository.useCases().save(item)
        #expect(try repository.useCases().listing().board.upcoming.map(\.day) == [Fix.day(2026, 11, 1)])
        try repository.useCases().payNow(itemID: item.id, occurrence: Fix.day(2026, 11, 1))
        #expect(try repository.useCases().listing().board.completed.map(\.id) == [item.id])
    }
}

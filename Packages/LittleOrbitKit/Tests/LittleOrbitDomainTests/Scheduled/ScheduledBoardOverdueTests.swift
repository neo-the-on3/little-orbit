import Foundation
import LittleOrbitDomain
import Testing

/// Where an item with missed occurrences shows (UI Designer, on Tech Architect NB 2): only under Overdue, one row
/// per missed day, plus Due Today when today is one of its days; never in Upcoming until the overdue ones are
/// settled. And what a device clock that was ahead at creation does (Tech Architect NB 3). Made-up data.
@MainActor
@Suite("Scheduled board with overdue items, and a creation day after today (#26)")
struct ScheduledBoardOverdueTests {
    private typealias Fix = ScheduledFixture

    private func manualRent(today: CalendarDay) throws -> (FakeScheduleRepository, ScheduledItem) {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let rent = Fix.rent(automatic: false)
        try repository.useCases().save(rent)
        repository.now = Fix.date(today.year, today.month, today.day)
        return (repository, rent)
    }

    @Test("Today's occurrence is under Due Today even while older ones are overdue")
    func dueTodayBesideOverdue() throws {
        let (repository, rent) = try manualRent(today: Fix.day(2026, 10, 1))
        let board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [Fix.day(2026, 8, 1), Fix.day(2026, 9, 1)])
        #expect(board.dueToday.map(\.day) == [Fix.day(2026, 10, 1)])
        #expect(board.dueToday.map(\.item.id) == [rent.id])
        #expect(board.upcoming.isEmpty)
    }

    @Test("No Upcoming row while the item has overdue ones; it returns once they're settled")
    func noUpcomingWhileOverdue() throws {
        let (repository, rent) = try manualRent(today: Fix.day(2026, 10, 20))
        var board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [Fix.day(2026, 8, 1), Fix.day(2026, 9, 1), Fix.day(2026, 10, 1)])
        #expect(board.dueToday.isEmpty)
        #expect(board.upcoming.isEmpty)
        for day in board.overdue.map(\.day) {
            try repository.useCases().payNow(itemID: rent.id, occurrence: day)
        }
        board = try repository.useCases().listing().board
        #expect(board.overdue.isEmpty)
        #expect(board.upcoming.map(\.day) == [Fix.day(2026, 11, 1)])
    }

    @Test("A clock ahead at creation hides occurrences until that day, and catch-up reports the item for the log")
    func creationDayAfterToday() throws {
        let repository = FakeScheduleRepository()
        // Created with the clock on 20 Dec 2026, then the clock is put right: today is 20 Oct.
        repository.now = Fix.date(2026, 12, 20)
        let rent = Fix.rent()
        try repository.useCases().save(rent)
        repository.now = Fix.date(2026, 10, 20)
        let result = try repository.useCases().catchUp(atLaunch: true)
        #expect(result.posted.isEmpty)
        #expect(result.createdAfterTodayItemIDs == [rent.id])
        let board = try repository.useCases().listing().board
        #expect(board.overdue.isEmpty && board.dueToday.isEmpty)
        #expect(board.upcoming.map(\.day) == [Fix.day(2027, 1, 1)])
        // From the creation day on, it's an ordinary item again.
        repository.now = Fix.date(2027, 1, 2)
        let later = try repository.useCases().catchUp(atLaunch: false)
        #expect(later.createdAfterTodayItemIDs.isEmpty)
        #expect(repository.posted(for: rent.id).map(TransactionTiming.day(of:)) == [Fix.day(2027, 1, 1)])
    }
}

import Foundation
import LittleOrbitDomain
import Testing

/// #202 with #316 (D433.1, D437.1, Tech Architect's #316 review). A move the user makes is kept: an "All future
/// occurrences" move into a period that already has one keeps the moved occurrence due on its new day, and the rule
/// goes on from there. Only real occurrences take a period: posted, skipped and pending ones, and ones with their
/// own values while their day is still on the rule, so a record left behind by a rule edit never takes one. An
/// occurrence whose day left the rule and that's due on another day takes only the one period of the current rule
/// that holds that day. Made-up data: Rent ₹25,000 monthly on the 1st from 1 Aug 2026, and Phone Plan ₹199 weekly
/// on Mondays, from Everyday Savings.
@MainActor
@Suite("Moved occurrences and leftover records in the period check (#202 with #316)")
struct ScheduledMovedPeriodTests {
    private typealias Fix = ScheduledFixture

    private func scene(_ item: ScheduledItem, today: CalendarDay) throws -> FakeScheduleRepository {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        try repository.useCases().save(item)
        repository.now = Fix.date(today.year, today.month, today.day)
        return repository
    }

    private func stored(_ repository: FakeScheduleRepository) throws -> ScheduledItem {
        try #require(repository.snapshot.scheduledItems.first)
    }

    private func move(
        _ key: CalendarDay,
        to day: CalendarDay,
        scope: ScheduledEditScope,
        in repository: FakeScheduleRepository,
        change: (inout ScheduledItem) -> Void = { _ in },
    ) throws {
        let current = try stored(repository)
        var form = current.resolved(for: key)
        form.occurrences = current.occurrences
        change(&form)
        _ = try repository.useCases()
            .update(
                form,
                editing: ScheduledOccurrenceSave(occurrence: key, dueDay: day, scope: scope),
                payee: nil,
            )
    }

    @Test("D433.1: 1 Oct paid, 1 Nov moved to 31 Oct for all future: 31 Oct is due, then 30 Nov")
    func allFutureIntoPaidMonth() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 10, 20))
        for month in 8...10 {
            _ = try repository.useCases()
                .pay(
                    itemID: rent.id,
                    occurrence: Fix.day(2026, month, 1),
                    on: Fix.day(2026, month, 1),
                    custom: nil,
                )
        }
        try move(Fix.day(2026, 11, 1), to: Fix.day(2026, 10, 31), scope: .allFuture, in: repository)
        let item = try stored(repository)
        let today = Fix.day(2026, 10, 20)
        #expect(
            ScheduleCalendar.firstOccurrence(of: item, onOrAfter: today) { !item.isSettled($0) }
                == Fix.day(2026, 10, 31)
        )
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 31), of: item))
        #expect(
            ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 30)).map(\.day)
                == [Fix.day(2026, 10, 31), Fix.day(2026, 11, 30)]
        )
        let board = try repository.useCases().listing().board
        #expect(board.upcoming.map(\.day).prefix(1) == [Fix.day(2026, 10, 31)])
    }

    @Test("D433.1: every 3 months, 15 Jan skipped, 15 Apr moved to 20 Mar for all future: 20 Mar is due, then 20 Jun")
    func allFutureEveryThreeMonths() throws {
        let water = Fix.rent(amount: 1_200, start: Fix.day(2027, 1, 15), rule: .every(3, .month), automatic: false)
        let repository = try scene(water, today: Fix.day(2027, 3, 1))
        _ = try repository.useCases().skip(itemID: water.id, occurrence: Fix.day(2027, 1, 15))
        try move(Fix.day(2027, 4, 15), to: Fix.day(2027, 3, 20), scope: .allFuture, in: repository)
        let item = try stored(repository)
        #expect(
            ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2027, 6, 30)).map(\.day)
                == [Fix.day(2027, 3, 20), Fix.day(2027, 6, 20)]
        )
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2027, 3, 20), of: item))
    }

    @Test("Tech Architect (b): 1 Dec has its own amount, Starts moved to the 5th: December still has one occurrence")
    func leftoverEditNeverTakesAPeriod() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 10, 20))
        for month in 8...10 {
            _ = try repository.useCases()
                .pay(
                    itemID: rent.id,
                    occurrence: Fix.day(2026, month, 1),
                    on: Fix.day(2026, month, 1),
                    custom: nil,
                )
        }
        let key = Fix.day(2026, 12, 1)
        try move(key, to: key, scope: .thisOccurrence, in: repository) { $0.amount = 26_000 }
        var moved = try stored(repository)
        moved.startDay = Fix.day(2026, 8, 5)
        try repository.useCases().save(moved)
        let item = try stored(repository)
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 12, 31)).map(\.day)
        #expect(due == [Fix.day(2026, 11, 5), Fix.day(2026, 12, 5)])
    }

    @Test("D432: Mon 9 Nov moved to Mon 2 Nov for this one only: 2 Nov keeps its own occurrence too")
    func thisOnlyMoveIntoAnotherWeek() throws {
        let phone = Fix.rent(amount: 199, start: Fix.day(2026, 10, 26), rule: .weekly, automatic: false)
        let repository = try scene(phone, today: Fix.day(2026, 10, 20))
        try move(Fix.day(2026, 11, 9), to: Fix.day(2026, 11, 2), scope: .thisOccurrence, in: repository)
        let item = try stored(repository)
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 16))
        #expect(
            due.map(\.day) == [
                Fix.day(2026, 10, 26), Fix.day(2026, 11, 2), Fix.day(2026, 11, 2), Fix.day(2026, 11, 16),
            ]
        )
    }

    @Test("1 Dec moved to 30 Nov for this one only: November keeps its own occurrence")
    func thisOnlyMoveIntoPreviousMonth() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 10, 20))
        try move(Fix.day(2026, 12, 1), to: Fix.day(2026, 11, 30), scope: .thisOccurrence, in: repository)
        let item = try stored(repository)
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 1), of: item))
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 12, 31)).map(\.day)
        #expect(due.suffix(2) == [Fix.day(2026, 11, 1), Fix.day(2026, 11, 30)])
    }
}

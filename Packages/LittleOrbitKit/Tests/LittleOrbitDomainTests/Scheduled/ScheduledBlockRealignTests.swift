import Foundation
import LittleOrbitDomain
import Testing

/// #316's checks 3 (D428.1), 4 and 5 (D429): a Starts edit on an every-N rule re-aligns its blocks to the new Starts
/// date, and a new block that overlaps an old one already holding an occurrence gets no new occurrence. Made-up
/// data: “Water Bill” ₹1,200 every 3 months, and “Cleaner” ₹6,000 every 2 weeks, from Everyday Savings, saved on
/// 1 Jan 2026 in `Asia/Kolkata`.
@MainActor
@Suite("Every-N blocks re-align after a Starts edit (D429)")
struct ScheduledBlockRealignTests {
    private typealias Fix = ScheduledFixture

    private func scene(
        _ rule: ScheduleRepeat,
        from start: CalendarDay,
        paying paid: [CalendarDay],
        today: CalendarDay,
    ) throws -> (FakeScheduleRepository, UUID) {
        let bill = Fix.rent(amount: 1_200, start: start, rule: rule, automatic: false)
        let repository = FakeScheduleRepository()
        repository.now = Fix.date(2026, 1, 1)
        try repository.useCases().save(bill)
        repository.now = Fix.date(today.year, today.month, today.day)
        for day in paid {
            _ = try repository.useCases().pay(itemID: bill.id, occurrence: day, on: day, custom: nil)
        }
        return (repository, bill.id)
    }

    private func moveStarts(to start: CalendarDay, in repository: FakeScheduleRepository) throws -> ScheduledItem {
        var item = try #require(repository.snapshot.scheduledItems.first)
        item.startDay = start
        try repository.useCases().save(item)
        return try #require(repository.snapshot.scheduledItems.first)
    }

    private func next(_ item: ScheduledItem, in repository: FakeScheduleRepository) -> CalendarDay? {
        ScheduleCalendar.firstOccurrence(of: item, onOrAfter: repository.useCases().today()) { !item.isSettled($0) }
    }

    @Test("Check 3: every 3 months from 15 Jan, 15 Oct paid, Starts to 25 Jan on 20 Oct: no 25 Oct; next 25 Jan")
    func checkThree() throws {
        let paid = [1, 4, 7, 10].map { Fix.day(2026, $0, 15) }
        let (repository, _) = try scene(.every(3, .month), from: paid[0], paying: paid, today: Fix.day(2026, 10, 20))
        let item = try moveStarts(to: Fix.day(2026, 1, 25), in: repository)
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 25), of: item))
        #expect(next(item, in: repository) == Fix.day(2027, 1, 25))
        #expect(try repository.useCases().listing().board.overdue.isEmpty)
    }

    @Test("Check 4: every 3 months from 15 Jan, 15 Jan paid, Starts to 10 Feb on 20 Feb: Feb–Apr is taken; next 10 May")
    func checkFour() throws {
        let (repository, id) = try scene(
            .every(3, .month),
            from: Fix.day(2026, 1, 15),
            paying: [Fix.day(2026, 1, 15)],
            today: Fix.day(2026, 2, 20),
        )
        let item = try moveStarts(to: Fix.day(2026, 2, 10), in: repository)
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 2, 10), of: item))
        #expect(next(item, in: repository) == Fix.day(2026, 5, 10))
        // The block itself: with the move made before 10 Feb, 10 Feb is still passed over.
        var early = item
        early.resumesOn = nil
        #expect(
            ScheduleCalendar.occurrences(of: early, through: Fix.day(2026, 8, 31))
                == [Fix.day(2026, 5, 10), Fix.day(2026, 8, 10)]
        )
        repository.now = Fix.date(2026, 5, 11)
        #expect(try repository.useCases().listing().board.overdue.map(\.day) == [Fix.day(2026, 5, 10)])
        #expect(repository.posted(for: id).count == 1)
    }

    @Test("Check 5: every 2 weeks from Mon 5 Oct, 5 Oct paid, Starts to Wed 14 Oct on 13 Oct: no 14 Oct; next 28 Oct")
    func checkFive() throws {
        let (repository, _) = try scene(
            .every(2, .week),
            from: Fix.day(2026, 10, 5),
            paying: [Fix.day(2026, 10, 5)],
            today: Fix.day(2026, 10, 13),
        )
        let item = try moveStarts(to: Fix.day(2026, 10, 14), in: repository)
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 14), of: item))
        #expect(next(item, in: repository) == Fix.day(2026, 10, 28))
        repository.now = Fix.date(2026, 10, 20)
        let board = try repository.useCases().listing().board
        #expect(board.overdue.isEmpty)
        #expect(board.upcoming.map(\.day) == [Fix.day(2026, 10, 28)])
    }
}

import Foundation
import LittleOrbitDomain
import Testing

/// D426.1 and D427.1 (#312 item 2): after the anchor moves, catch-up and every due list skip a period of the new
/// rule that already has an occurrence of the item, paid, skipped or still open, so a month never gets a second
/// Rent. A period is the rule's calendar unit, so a monthly rule's is the calendar month. A period with no
/// occurrence is still due, and is caught up as usual. Made-up data: Rent ₹25,000 monthly on the 1st from
/// 1 Aug 2026, from Everyday Savings, in `Asia/Kolkata`.
@MainActor
@Suite("Catch-up skips a period already recorded after an anchor move (D426.1)")
struct ScheduledRecordedPeriodTests {
    private typealias Fix = ScheduledFixture

    private func scene(automatic: Bool, today: CalendarDay) throws -> (FakeScheduleRepository, ScheduledItem) {
        var rent = Fix.rent(automatic: automatic)
        rent.notifiesWhenDue = true
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        try repository.useCases().save(rent)
        repository.now = Fix.date(today.year, today.month, today.day)
        return (repository, rent)
    }

    private func stored(_ repository: FakeScheduleRepository) throws -> ScheduledItem {
        try #require(repository.snapshot.scheduledItems.first)
    }

    private func pay(_ id: UUID, _ day: CalendarDay, in repository: FakeScheduleRepository) throws {
        _ = try repository.useCases().pay(itemID: id, occurrence: day, on: day, custom: nil)
    }

    /// Moves the anchor from the 1st to the 5th, from 5 Aug, as a Starts edit saved today.
    private func moveToFifth(in repository: FakeScheduleRepository) throws {
        var item = try stored(repository)
        item.startDay = Fix.day(2026, 8, 5)
        try repository.useCases().save(item)
    }

    private func posted(_ id: UUID, in repository: FakeScheduleRepository, month: Int) -> [Transaction] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: Fix.zone)!
        return repository.posted(for: id).filter { calendar.component(.month, from: $0.date) == month }
    }

    private func next(_ repository: FakeScheduleRepository) throws -> CalendarDay? {
        let item = try stored(repository)
        let today = repository.useCases().today()
        return ScheduleCalendar.firstOccurrence(of: item, onOrAfter: today) { !item.isSettled($0) }
    }

    @Test("Check 1: 1 Sep and 1 Oct paid, moved to the 5th: no 5 Oct anywhere, and the next one is 5 Nov")
    func paidPeriodSkipped() throws {
        let (repository, rent) = try scene(automatic: false, today: Fix.day(2026, 10, 3))
        for month in 8...10 {
            try pay(rent.id, Fix.day(2026, month, 1), in: repository)
        }
        try moveToFifth(in: repository)
        let october = Fix.day(2026, 10, 5)
        let item = try stored(repository)
        #expect(!ScheduleCalendar.isOccurrence(october, of: item))
        #expect(try next(repository) == Fix.day(2026, 11, 5))
        repository.now = Fix.date(2026, 10, 20)
        let board = try repository.useCases().listing().board
        #expect(board.overdue.isEmpty)
        #expect(board.overdueCount == 0)
        #expect(board.upcoming.map(\.day) == [Fix.day(2026, 11, 5)])
        #expect(ScheduleCalendar.dueDays(of: item, through: Fix.day(2026, 10, 31)).isEmpty)
        // No reminder for it either.
        let reminders = ScheduledReminderPlanner.plan(
            [item],
            now: Fix.date(2026, 10, 3, 8),
            timeZone: TimeZone(identifier: Fix.zone)!,
            time: .standard,
            limit: 2,
        )
        #expect(reminders.map(\.day) == [Fix.day(2026, 11, 5), Fix.day(2026, 12, 5)])
    }

    @Test("Check 2: automatic, relaunched on 6 Nov: catch-up records one Rent, on 5 Nov; October keeps one")
    func automaticCatchUp() throws {
        let (repository, rent) = try scene(automatic: true, today: Fix.day(2026, 10, 3))
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.count == 3)
        try moveToFifth(in: repository)
        let before = try LedgerBook.balance(of: Fix.savingsID, in: repository.snapshot)
        repository.now = Fix.date(2026, 11, 6)
        let launch = try repository.useCases().catchUp(atLaunch: true)
        #expect(launch.posted.count == 1)
        #expect(launch.posted.first?.scheduledOccurrenceDate == Fix.date(2026, 11, 5, 12))
        #expect(posted(rent.id, in: repository, month: 10).count == 1)
        #expect(posted(rent.id, in: repository, month: 11).map(\.amount) == [25_000])
        #expect(try LedgerBook.balance(of: Fix.savingsID, in: repository.snapshot) == before - 25_000)
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
    }

    @Test("Check 3: 1 Sep paid and 1 Oct skipped: a skip counts as recorded, so no 5 Oct; next is 5 Nov")
    func skippedPeriodSkipped() throws {
        let (repository, rent) = try scene(automatic: false, today: Fix.day(2026, 10, 3))
        try pay(rent.id, Fix.day(2026, 8, 1), in: repository)
        try pay(rent.id, Fix.day(2026, 9, 1), in: repository)
        _ = try repository.useCases().skip(itemID: rent.id, occurrence: Fix.day(2026, 10, 1))
        try moveToFifth(in: repository)
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 5), of: try stored(repository)))
        #expect(try next(repository) == Fix.day(2026, 11, 5))
        repository.now = Fix.date(2026, 10, 20)
        #expect(try repository.useCases().listing().board.overdue.isEmpty)
    }

    @Test("A period with nothing recorded is still due: moved on 3 Sep, 5 Oct is caught up on 6 Oct")
    func emptyPeriodCaughtUp() throws {
        let (repository, rent) = try scene(automatic: true, today: Fix.day(2026, 9, 3))
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.count == 2)
        try moveToFifth(in: repository)
        // 5 Sep's period has 1 Sep, so it's skipped; 5 Oct's has nothing recorded.
        repository.now = Fix.date(2026, 10, 6)
        let launch = try repository.useCases().catchUp(atLaunch: true)
        #expect(launch.posted.count == 1)
        #expect(launch.posted.first?.scheduledOccurrenceDate == Fix.date(2026, 10, 5, 12))
        #expect(posted(rent.id, in: repository, month: 9).count == 1)
        #expect(posted(rent.id, in: repository, month: 10).count == 1)
    }

    /// Moved on 3 Oct, before the new rule's 5 Oct, so only the open 1 Oct keeps 5 Oct out; and on 20 Oct.
    @Test(
        "Check 7: 1 Sep paid and 1 Oct overdue: October keeps only the open 1 Oct, counted once; next is 5 Nov",
        arguments: [ScheduledFixture.day(2026, 10, 3), ScheduledFixture.day(2026, 10, 20)],
    )
    func overduePeriodKeepsItsOccurrence(movedOn today: CalendarDay) throws {
        let (repository, rent) = try scene(automatic: false, today: today)
        try pay(rent.id, Fix.day(2026, 8, 1), in: repository)
        try pay(rent.id, Fix.day(2026, 9, 1), in: repository)
        try moveToFifth(in: repository)
        let item = try stored(repository)
        #expect(item.occurrence(on: Fix.day(2026, 10, 1))?.outcome == .pending)
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 5), of: item))
        #expect(ScheduleCalendar.dueDays(of: item, through: Fix.day(2026, 10, 31)) == [Fix.day(2026, 10, 1)])
        #expect(try next(repository) == Fix.day(2026, 11, 5))
        repository.now = Fix.date(2026, 10, 20)
        let board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [Fix.day(2026, 10, 1)])
        #expect(board.overdueCount == 1)
    }

    @Test("Check 8: paying the open 1 Oct never brings 5 Oct back; 6 Nov posts only 5 Nov, ₹50,000 in all")
    func payingOverdueKeepsPeriodTaken() throws {
        let (repository, rent) = try scene(automatic: false, today: Fix.day(2026, 10, 3))
        try pay(rent.id, Fix.day(2026, 8, 1), in: repository)
        try pay(rent.id, Fix.day(2026, 9, 1), in: repository)
        try moveToFifth(in: repository)
        let before = try LedgerBook.balance(of: Fix.savingsID, in: repository.snapshot)
        try pay(rent.id, Fix.day(2026, 10, 1), in: repository)
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 5), of: try stored(repository)))
        var automatic = try stored(repository)
        automatic.processesAutomatically = true
        try repository.useCases().save(automatic)
        repository.now = Fix.date(2026, 11, 6)
        let launch = try repository.useCases().catchUp(atLaunch: true)
        #expect(launch.posted.map(\.scheduledOccurrenceDate) == [Fix.date(2026, 11, 5, 12)])
        #expect(posted(rent.id, in: repository, month: 10).map(\.amount) == [25_000])
        #expect(posted(rent.id, in: repository, month: 11).map(\.amount) == [25_000])
        #expect(try LedgerBook.balance(of: Fix.savingsID, in: repository.snapshot) == before - 50_000)
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 5), of: try stored(repository)))
    }

    private func item(
        _ rule: ScheduleRepeat,
        from start: CalendarDay,
        recording day: CalendarDay,
        _ outcome: ScheduledOutcome,
    ) -> ScheduledItem {
        var item = Fix.rent(start: start, rule: rule)
        item.occurrences = [ScheduledOccurrence(id: UUID(), day: day, outcome: outcome, createdAt: Fix.created)]
        return item
    }

    @Test(
        "A period is the rule's calendar unit: an occurrence in the same month takes it; the previous month's doesn't",
        arguments: [
            (Fix.day(2026, 12, 28), ScheduledOutcome.posted, [Fix.day(2027, 1, 5), Fix.day(2027, 2, 5)]),
            (Fix.day(2026, 1, 20), ScheduledOutcome.posted, [Fix.day(2027, 1, 5), Fix.day(2027, 2, 5)]),
            (Fix.day(2027, 1, 2), ScheduledOutcome.pending, [Fix.day(2027, 2, 5)]),
            (Fix.day(2027, 1, 31), ScheduledOutcome.skipped, [Fix.day(2027, 2, 5)]),
            (Fix.day(2027, 1, 5), ScheduledOutcome.posted, [Fix.day(2027, 1, 5), Fix.day(2027, 2, 5)]),
        ],
    )
    func monthlyPeriod(recorded: CalendarDay, outcome: ScheduledOutcome, expected: [CalendarDay]) {
        let rent = item(.monthly, from: Fix.day(2027, 1, 5), recording: recorded, outcome)
        #expect(ScheduleCalendar.occurrences(of: rent, through: Fix.day(2027, 2, 28)) == expected)
    }

    @Test("Paid on 28 Oct and moved from the 28th to the 1st: 1 Nov is November's, so it's still due")
    func earlierAnchorNextMonth() throws {
        var rent = Fix.rent(start: Fix.day(2026, 8, 28), automatic: false)
        rent.createdAt = Fix.created
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        try repository.useCases().save(rent)
        repository.now = Fix.date(2026, 10, 29)
        for month in 8...10 {
            try pay(rent.id, Fix.day(2026, month, 28), in: repository)
        }
        var moved = try stored(repository)
        moved.startDay = Fix.day(2026, 9, 1)
        try repository.useCases().save(moved)
        #expect(try next(repository) == Fix.day(2026, 11, 1))
    }

    @Test(
        "Weekly periods are ISO weeks, Monday first; yearly periods are calendar years",
        arguments: [
            // Weekly from Wed 4 Nov 2026: Mon 2 Nov is the same week, Sun 1 Nov the week before.
            (ScheduleRepeat.weekly, Fix.day(2026, 11, 4), Fix.day(2026, 11, 2), false),
            (ScheduleRepeat.weekly, Fix.day(2026, 11, 4), Fix.day(2026, 11, 1), true),
            (ScheduleRepeat.yearly, Fix.day(2027, 3, 1), Fix.day(2027, 1, 15), false),
            (ScheduleRepeat.yearly, Fix.day(2027, 3, 1), Fix.day(2026, 12, 31), true),
            (ScheduleRepeat.daily, Fix.day(2026, 11, 4), Fix.day(2026, 11, 3), true),
        ],
    )
    func otherUnits(rule: ScheduleRepeat, start: CalendarDay, recorded: CalendarDay, startIsDue: Bool) {
        let scheduled = item(rule, from: start, recording: recorded, .posted)
        #expect(ScheduleCalendar.isOccurrence(start, of: scheduled) == startIsDue)
    }

    @Test("A one-off item has no periods")
    func oneOff() {
        let once = item(.never, from: Fix.day(2026, 11, 20), recording: Fix.day(2026, 11, 2), .skipped)
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 20), of: once))
    }

    @Test("A deleted record leaves its period open")
    func deletedRecord() {
        var rent = item(.monthly, from: Fix.day(2026, 8, 5), recording: Fix.day(2026, 10, 1), .posted)
        rent.occurrences[0].deletedAt = Fix.created
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 5), of: rent))
    }

    @Test("An item whose anchor never moved is untouched: every month is due and caught up")
    func unmovedItem() throws {
        let (repository, rent) = try scene(automatic: true, today: Fix.day(2026, 11, 2))
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.count == 4)
        #expect(repository.posted(for: rent.id).count == 4)
    }
}

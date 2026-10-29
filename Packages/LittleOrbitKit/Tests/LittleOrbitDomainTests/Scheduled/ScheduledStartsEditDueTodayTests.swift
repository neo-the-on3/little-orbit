import Foundation
import LittleOrbitDomain
import Testing

/// D428.2 (#312 item 2): a Starts edit saved on the day an occurrence is due keeps today's unpaid occurrence, which
/// is still due (D427.2), on its own day, and the new anchor starts in the next period. Before D428.2 it was dropped
/// silently, because only days before today were kept (D336.1, which still holds for those days). Today is the
/// device's day, in the time zone the use cases read. Made-up data: Rent ₹25,000 monthly on the 1st from 1 Aug 2026,
/// from Everyday Savings, with 1 Aug, 1 Sep and 1 Oct paid.
@MainActor
@Suite("A Starts edit on the due day keeps today's occurrence (D428.2)")
struct ScheduledStartsEditDueTodayTests {
    private typealias Fix = ScheduledFixture

    private static let utc = "UTC"

    /// Rent, with August to October paid, and the clock at `now`.
    private func scene(now: Date) throws -> (FakeScheduleRepository, UUID) {
        let rent = Fix.rent(automatic: false)
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        try repository.useCases().save(rent)
        repository.now = Fix.date(2026, 10, 2)
        for month in 8...10 {
            _ = try repository.useCases()
                .pay(
                    itemID: rent.id,
                    occurrence: Fix.day(2026, month, 1),
                    on: Fix.day(2026, month, 1),
                    custom: nil,
                )
        }
        repository.now = now
        return (repository, rent.id)
    }

    private func stored(_ repository: FakeScheduleRepository) throws -> ScheduledItem {
        try #require(repository.snapshot.scheduledItems.first)
    }

    /// Saves a Starts or repeat edit through the use cases that read the clock in `zone`.
    private func edit(
        in repository: FakeScheduleRepository,
        zone: String = Fix.zone,
        _ change: (inout ScheduledItem) -> Void,
    ) throws {
        var item = try stored(repository)
        change(&item)
        try repository.useCases(zone: zone).save(item)
    }

    private func next(_ repository: FakeScheduleRepository, zone: String = Fix.zone) throws -> CalendarDay? {
        let item = try stored(repository)
        let today = repository.useCases(zone: zone).today()
        return ScheduleCalendar.firstOccurrence(of: item, onOrAfter: today) { !item.isSettled($0) }
    }

    @Test("Moved to the 5th on 1 Nov with 1 Nov unpaid: 1 Nov stays due today, no 5 Nov, next is 5 Dec")
    func keepsTodaysOccurrence() throws {
        let (repository, id) = try scene(now: Fix.date(2026, 11, 1))
        try edit(in: repository) { $0.startDay = Fix.day(2026, 8, 5) }
        let item = try stored(repository)
        #expect(item.occurrence(on: Fix.day(2026, 11, 1))?.outcome == .pending)
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 1), of: item))
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 5), of: item))
        #expect(ScheduleCalendar.dueDays(of: item, through: Fix.day(2026, 11, 30)) == [Fix.day(2026, 11, 1)])
        let board = try repository.useCases().listing().board
        #expect(board.dueToday.map(\.day) == [Fix.day(2026, 11, 1)])
        #expect(board.overdue.isEmpty)
        #expect(try next(repository) == Fix.day(2026, 12, 5))
        // Paying it records it once on 1 Nov and never brings 5 Nov back.
        let before = try LedgerBook.balance(of: Fix.savingsID, in: repository.snapshot)
        _ = try repository.useCases()
            .pay(itemID: id, occurrence: Fix.day(2026, 11, 1), on: Fix.day(2026, 11, 1), custom: nil)
        #expect(try LedgerBook.balance(of: Fix.savingsID, in: repository.snapshot) == before - 25_000)
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 5), of: try stored(repository)))
        #expect(repository.posted(for: id).count == 4)
    }

    @Test("Skipping the kept 1 Nov counts as November's occurrence too: next is 5 Dec")
    func skippedKeptDay() throws {
        let (repository, id) = try scene(now: Fix.date(2026, 11, 1))
        try edit(in: repository) { $0.startDay = Fix.day(2026, 8, 5) }
        _ = try repository.useCases().skip(itemID: id, occurrence: Fix.day(2026, 11, 1))
        #expect(try stored(repository).occurrence(on: Fix.day(2026, 11, 1))?.outcome == .skipped)
        #expect(try next(repository) == Fix.day(2026, 12, 5))
    }

    @Test("Today's occurrence already paid: nothing is kept, and the next is 5 Dec as before")
    func paidTodayUnchanged() throws {
        let (repository, id) = try scene(now: Fix.date(2026, 11, 1))
        _ = try repository.useCases()
            .pay(itemID: id, occurrence: Fix.day(2026, 11, 1), on: Fix.day(2026, 11, 1), custom: nil)
        try edit(in: repository) { $0.startDay = Fix.day(2026, 8, 5) }
        #expect(try stored(repository).occurrence(on: Fix.day(2026, 11, 1))?.outcome == .posted)
        #expect(try next(repository) == Fix.day(2026, 12, 5))
        #expect(repository.posted(for: id).count == 4)
    }

    @Test("A day before today is unchanged (D336.1): moved on 2 Nov, the unpaid 1 Nov stays overdue; next 5 Dec")
    func dayBeforeTodayUnchanged() throws {
        let (repository, _) = try scene(now: Fix.date(2026, 11, 2))
        try edit(in: repository) { $0.startDay = Fix.day(2026, 8, 5) }
        #expect(try stored(repository).occurrence(on: Fix.day(2026, 11, 1))?.outcome == .pending)
        let board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [Fix.day(2026, 11, 1)])
        #expect(try next(repository) == Fix.day(2026, 12, 5))
    }

    @Test("Nothing due today: moved on 31 Oct, nothing is kept and the next is 5 Nov")
    func nothingDueToday() throws {
        let (repository, _) = try scene(now: Fix.date(2026, 10, 31))
        try edit(in: repository) { $0.startDay = Fix.day(2026, 8, 5) }
        #expect(try stored(repository).occurrences.allSatisfy { $0.outcome == .posted })
        #expect(try next(repository) == Fix.day(2026, 11, 5))
    }

    @Test("Today's day is also on the new rule: it's due once, and paid once")
    func todayOnBothRules() throws {
        let (repository, id) = try scene(now: Fix.date(2026, 11, 1))
        try edit(in: repository) {
            $0.startDay = Fix.day(2026, 9, 1)
            $0.repeatRule = .every(2, .month)
        }
        let item = try stored(repository)
        #expect(ScheduleCalendar.dueDays(of: item, through: Fix.day(2026, 12, 31)) == [Fix.day(2026, 11, 1)])
        #expect(try repository.useCases().listing().board.dueToday.count == 1)
        _ = try repository.useCases()
            .pay(itemID: id, occurrence: Fix.day(2026, 11, 1), on: Fix.day(2026, 11, 1), custom: nil)
        #expect(repository.posted(for: id).count == 4)
        #expect(try next(repository) == Fix.day(2027, 1, 1))
    }

    /// 00:10 on 1 Nov in Kolkata is 18:40 on 31 Oct in UTC. The device's zone decides which day is today.
    @Test("Near midnight, the device's zone decides today: 00:10 1 Nov in Kolkata keeps 1 Nov; in UTC it's 31 Oct")
    func midnightInDeviceZone() throws {
        let instant = Fix.date(2026, 11, 1, 0).addingTimeInterval(10 * 60)
        let (kolkata, _) = try scene(now: instant)
        try edit(in: kolkata) { $0.startDay = Fix.day(2026, 8, 5) }
        #expect(try stored(kolkata).occurrence(on: Fix.day(2026, 11, 1))?.outcome == .pending)
        #expect(try next(kolkata) == Fix.day(2026, 12, 5))

        let (utc, _) = try scene(now: instant)
        try edit(in: utc, zone: Self.utc) { $0.startDay = Fix.day(2026, 8, 5) }
        #expect(try stored(utc).occurrence(on: Fix.day(2026, 11, 1)) == nil)
        #expect(try next(utc, zone: Self.utc) == Fix.day(2026, 11, 5))
    }

    @Test("Just before midnight in Kolkata, 23:50 on 31 Oct, 1 Nov isn't due yet: next is 5 Nov")
    func justBeforeMidnight() throws {
        let (repository, _) = try scene(now: Fix.date(2026, 10, 31, 23).addingTimeInterval(50 * 60))
        try edit(in: repository) { $0.startDay = Fix.day(2026, 8, 5) }
        #expect(try stored(repository).occurrence(on: Fix.day(2026, 11, 1)) == nil)
        #expect(try next(repository) == Fix.day(2026, 11, 5))
    }
}

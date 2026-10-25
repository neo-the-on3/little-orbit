import Foundation
import LittleOrbitDomain
import Testing

/// D336 and D337: an edit to the start or the repeat never drops an unpaid overdue occurrence, and nothing before
/// the day an item was created is ever due, overdue or recorded. Made-up data.
@MainActor
@Suite("Scheduled edits and creation day (#26, D336, D337)")
struct ScheduledEditAndCreationTests {
    private typealias Fix = ScheduledFixture

    /// A manual Rent, monthly on the 1st from 1 Aug, created on 1 Jul; today is 20 Oct.
    private func rentScene(payAugust: Bool) throws -> (FakeScheduleRepository, ScheduledItem) {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let rent = Fix.rent(automatic: false)
        try repository.useCases().save(rent)
        repository.now = Fix.date(2026, 10, 20)
        if payAugust {
            try repository.useCases().payNow(itemID: rent.id, occurrence: Fix.day(2026, 8, 1))
        }
        return (repository, rent)
    }

    private func moveStart(of rent: ScheduledItem, in repository: FakeScheduleRepository) throws {
        var edited = try #require(repository.snapshot.scheduledItems.first { $0.id == rent.id })
        edited.startDay = Fix.day(2026, 8, 5)
        try repository.useCases().save(edited)
    }

    /// The new rule's first day after today.
    private func nextDue(_ rent: ScheduledItem, in repository: FakeScheduleRepository) throws -> CalendarDay? {
        let item = try #require(repository.snapshot.scheduledItems.first { $0.id == rent.id })
        return ScheduleCalendar.firstOccurrence(of: item, onOrAfter: Fix.day(2026, 10, 21), where: { _ in true })
    }

    @Test("D336 (a): with Aug paid, moving the start to the 5th keeps 1 Sep and 1 Oct overdue; next is 5 Nov")
    func editAfterAPayment() throws {
        let (repository, rent) = try rentScene(payAugust: true)
        let before = try repository.useCases().listing().board
        #expect(before.overdue.map(\.day) == [Fix.day(2026, 9, 1), Fix.day(2026, 10, 1)])
        try moveStart(of: rent, in: repository)
        let board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [Fix.day(2026, 9, 1), Fix.day(2026, 10, 1)])
        #expect(board.overdueCount == 2)
        #expect(try nextDue(rent, in: repository) == Fix.day(2026, 11, 5))
        #expect(repository.posted(for: rent.id).count == 1)
    }

    @Test("D336 (b): with nothing settled, the overdue days stay on the 1st and never move to the 5th")
    func editWithNothingSettled() throws {
        let (repository, rent) = try rentScene(payAugust: false)
        try moveStart(of: rent, in: repository)
        let board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [Fix.day(2026, 8, 1), Fix.day(2026, 9, 1), Fix.day(2026, 10, 1)])
        #expect(!board.overdue.contains { $0.day.day == 5 })
        #expect(try nextDue(rent, in: repository) == Fix.day(2026, 11, 5))
    }

    @Test("D336.1: a kept day pays or skips once, under its own key, and a second edit keeps the rest")
    func keptDaysSettle() throws {
        let (repository, rent) = try rentScene(payAugust: false)
        try moveStart(of: rent, in: repository)
        let useCases = repository.useCases()
        let paid = try useCases.payNow(itemID: rent.id, occurrence: Fix.day(2026, 9, 1))
        #expect(paid?.id == ScheduledKey.transactionID(item: rent.id, day: Fix.day(2026, 9, 1)))
        #expect(try useCases.payNow(itemID: rent.id, occurrence: Fix.day(2026, 9, 1)) == nil)
        try useCases.skip(itemID: rent.id, occurrence: Fix.day(2026, 8, 1))
        var edited = try #require(repository.snapshot.scheduledItems.first)
        edited.repeatRule = .every(2, .month)
        try useCases.save(edited)
        let board = try useCases.listing().board
        #expect(board.overdue.map(\.day) == [Fix.day(2026, 10, 1)])
        let item = try #require(repository.snapshot.scheduledItems.first)
        #expect(item.occurrences.map(\.outcome) == [.skipped, .posted, .pending])
        #expect(Set(item.occurrences.map(\.day)).count == item.occurrences.count)
        try LedgerBook.validateStoredScheduledItems(in: repository.snapshot)
    }

    @Test("D336.1: an amount-only edit adds no records and moves nothing")
    func amountEdit() throws {
        let (repository, rent) = try rentScene(payAugust: false)
        var edited = try #require(repository.snapshot.scheduledItems.first)
        edited.amount = 26_000
        try repository.useCases().save(edited)
        #expect(repository.snapshot.scheduledItems.first?.occurrences.isEmpty == true)
        #expect(try repository.useCases().listing().board.overdue.count == 3)
        #expect(rent.amount == 25_000)
    }

    @Test("D336.2: an automatic item from 1 Aug created on 20 Oct records nothing before 1 Nov")
    func catchUpStartsOnTheCreationDay() throws {
        let repository = FakeScheduleRepository()
        repository.now = Fix.date(2026, 10, 20)
        let rent = Fix.rent()
        try repository.useCases().save(rent)
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
        #expect(try repository.useCases().listing().board.upcoming.map(\.day) == [Fix.day(2026, 11, 1)])
        // Away until 2 Feb: Nov, Dec, Jan and Feb are recorded in one catch-up, grouped for the hint.
        repository.now = Fix.date(2027, 2, 2)
        let result = try repository.useCases().catchUp(atLaunch: true)
        #expect(
            repository.posted(for: rent.id).map(TransactionTiming.day(of:)) == [
                Fix.day(2026, 11, 1), Fix.day(2026, 12, 1), Fix.day(2027, 1, 1), Fix.day(2027, 2, 1),
            ]
        )
        let group = ScheduledCatchUpGroup(
            itemID: rent.id,
            days: [Fix.day(2026, 11, 1), Fix.day(2026, 12, 1), Fix.day(2027, 1, 1), Fix.day(2027, 2, 1)],
        )
        #expect(result.recordedByItem == [group])
        #expect(result.recordedByItem.first?.count == 4)
    }

    @Test("D336.2: an occurrence on the creation day itself is recorded")
    func creationDayCounts() throws {
        let repository = FakeScheduleRepository()
        repository.now = Fix.date(2026, 10, 20)
        let gym = Fix.rent(start: Fix.day(2026, 8, 20))
        try repository.useCases().save(gym)
        #expect(
            try repository.useCases().catchUp(atLaunch: true).posted.map(TransactionTiming.day(of:)) == [
                Fix.day(2026, 10, 20)
            ]
        )
    }

    @Test("D337.1: a manual item from 1 Aug added on 20 Oct shows no overdue rows and is next due 1 Nov")
    func manualStartsOnTheCreationDay() throws {
        let repository = FakeScheduleRepository()
        repository.now = Fix.date(2026, 10, 20)
        let rent = Fix.rent(automatic: false)
        try repository.useCases().save(rent)
        var board = try repository.useCases().listing().board
        #expect(board.overdue.isEmpty && board.dueToday.isEmpty)
        #expect(board.overdueCount == 0)
        #expect(board.upcoming.map(\.day) == [Fix.day(2026, 11, 1)])
        // Unpaid after creation: overdue as before (D59, D106).
        repository.now = Fix.date(2026, 12, 3)
        board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [Fix.day(2026, 11, 1), Fix.day(2026, 12, 1)])
        #expect(throws: LedgerValidationError.notAnOccurrence) {
            try repository.useCases().payNow(itemID: rent.id, occurrence: Fix.day(2026, 10, 1))
        }
    }

    @Test("Catch-up groups what it recorded by item, in the order the items were recorded")
    func groupsByItem() {
        let rentID = UUID()
        let gymID = UUID()
        func posted(_ itemID: UUID, _ day: CalendarDay) -> Transaction {
            Transaction(
                type: .expense,
                amount: 1,
                date: Fix.date(day.year, day.month, day.day, 12),
                timeZoneID: Fix.zone,
                accountID: Fix.savingsID,
                scheduledTemplateID: itemID,
                scheduledOccurrenceDate: Fix.date(day.year, day.month, day.day, 12),
                createdAt: Fix.created,
            )
        }
        let result = ScheduledCatchUp(posted: [
            posted(rentID, Fix.day(2026, 9, 1)),
            posted(gymID, Fix.day(2026, 8, 18)),
            posted(rentID, Fix.day(2026, 8, 1)),
            Transaction(type: .expense, amount: 1, accountID: Fix.savingsID, createdAt: Fix.created),
        ])
        #expect(
            result.recordedByItem == [
                ScheduledCatchUpGroup(itemID: rentID, days: [Fix.day(2026, 8, 1), Fix.day(2026, 9, 1)]),
                ScheduledCatchUpGroup(itemID: gymID, days: [Fix.day(2026, 8, 18)]),
            ]
        )
        #expect(ScheduledCatchUp().recordedByItem.isEmpty)
    }

    @Test("D338.6: merging a later catch-up adds new days per item, without repeats, and new items last")
    func mergingGroups() {
        let rentID = UUID()
        let salaryID = UUID()
        let earlier = [ScheduledCatchUpGroup(itemID: rentID, days: [Fix.day(2026, 8, 1), Fix.day(2026, 9, 1)])]
        let later = [
            ScheduledCatchUpGroup(itemID: salaryID, days: [Fix.day(2026, 10, 1)]),
            ScheduledCatchUpGroup(itemID: rentID, days: [Fix.day(2026, 10, 1), Fix.day(2026, 9, 1)]),
        ]
        let merged = ScheduledCatchUpGroup.merging(earlier, with: later)
        #expect(merged.map(\.itemID) == [rentID, salaryID])
        #expect(merged.first?.days == [Fix.day(2026, 8, 1), Fix.day(2026, 9, 1), Fix.day(2026, 10, 1)])
        #expect(merged.map(\.count) == [3, 1])
        #expect(ScheduledCatchUpGroup.merging([], with: []).isEmpty)
    }
}

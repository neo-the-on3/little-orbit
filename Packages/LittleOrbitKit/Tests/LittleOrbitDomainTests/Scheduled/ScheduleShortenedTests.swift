import Foundation
import LittleOrbitDomain
import Testing

/// "Last day" marks only an occurrence moved to a month's last day because the month is shorter than the rule's
/// day (D24), never a day kept from before a Starts edit (D336.1, Tester's 8a99da5 Mac pass). Made-up data.
@MainActor
@Suite("Scheduled shortened month ends (#26, D24)")
struct ScheduleShortenedTests {
    private typealias Fix = ScheduledFixture

    @Test("A monthly item on the 31st is shortened in 30-day months and February, and not in 31-day months")
    func realShortMonths() {
        let item = Fix.rent(start: Fix.day(2026, 8, 31))
        #expect(ScheduleCalendar.isShortened(Fix.day(2026, 9, 30), of: item))
        #expect(ScheduleCalendar.isShortened(Fix.day(2027, 2, 28), of: item))
        #expect(!ScheduleCalendar.isShortened(Fix.day(2026, 10, 31), of: item))
    }

    @Test("A monthly item on the 30th is shortened only in February, and the 29th only outside leap years")
    func thirtiethAndTwentyNinth() {
        let thirtieth = Fix.rent(start: Fix.day(2026, 8, 30))
        #expect(!ScheduleCalendar.isShortened(Fix.day(2026, 9, 30), of: thirtieth))
        #expect(ScheduleCalendar.isShortened(Fix.day(2028, 2, 29), of: thirtieth))
        let twentyNinth = Fix.rent(start: Fix.day(2026, 8, 29))
        #expect(ScheduleCalendar.isShortened(Fix.day(2027, 2, 28), of: twentyNinth))
        #expect(!ScheduleCalendar.isShortened(Fix.day(2028, 2, 29), of: twentyNinth))
    }

    @Test("A yearly 29 Feb item is shortened on 28 Feb only; a kept earlier day in another month isn't")
    func yearly() {
        let item = Fix.rent(start: Fix.day(2028, 2, 29), rule: .yearly)
        #expect(ScheduleCalendar.isShortened(Fix.day(2029, 2, 28), of: item))
        #expect(!ScheduleCalendar.isShortened(Fix.day(2032, 2, 29), of: item))
        #expect(!ScheduleCalendar.isShortened(Fix.day(2029, 1, 31), of: item))
    }

    @Test("A day earlier than the anchor that isn't the month's last day isn't shortened")
    func earlierDayIsNotShortened() {
        let item = Fix.rent(start: Fix.day(2026, 8, 16), rule: .every(2, .month))
        #expect(!ScheduleCalendar.isShortened(Fix.day(2026, 10, 15), of: item))
        #expect(!ScheduleCalendar.isShortened(Fix.day(2026, 10, 16), of: item))
        let never = Fix.rent(start: Fix.day(2026, 8, 31), rule: .never)
        #expect(!ScheduleCalendar.isShortened(Fix.day(2026, 9, 30), of: never))
    }

    @Test("Starts moved from 15 Aug to 16 Aug: the kept unpaid 15 Oct stays overdue and isn't a shortened month end")
    func keptDayAfterStartsEdit() throws {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let electricity = Fix.rent(start: Fix.day(2026, 8, 15), rule: .every(2, .month), automatic: false)
        try repository.useCases().save(electricity)
        repository.now = Fix.date(2026, 10, 20)
        try repository.useCases().skip(itemID: electricity.id, occurrence: Fix.day(2026, 8, 15))
        var edited = try #require(repository.snapshot.scheduledItems.first { $0.id == electricity.id })
        edited.startDay = Fix.day(2026, 8, 16)
        try repository.useCases().save(edited)
        let board = try repository.useCases().listing().board
        let kept = try #require(board.overdue.first { $0.item.id == electricity.id })
        #expect(kept.day == Fix.day(2026, 10, 15))
        #expect(!ScheduleCalendar.isShortened(kept.day, of: kept.item))
    }

    @Test("D373: a 30th rule on 30 Sep has no note; a 31st rule's own 30 Sep has one")
    func ruleDayExistsOrNot() {
        #expect(!ScheduleCalendar.isShortened(Fix.day(2026, 9, 30), of: Fix.rent(start: Fix.day(2026, 8, 30))))
        #expect(ScheduleCalendar.isShortened(Fix.day(2026, 9, 30), of: Fix.rent(start: Fix.day(2026, 8, 31))))
    }

    @Test("D373: a day the current rule doesn't generate that month never has the note")
    func notTheRulesOwnDay() {
        // A monthly rule on the 15th: 28 Feb is a month end, but the rule's February day is 15 Feb.
        #expect(!ScheduleCalendar.isShortened(Fix.day(2027, 2, 28), of: Fix.rent(start: Fix.day(2027, 1, 15))))
        // Every 2 months from 31 Jan falls in March and May, not April.
        let everyTwo = Fix.rent(start: Fix.day(2027, 1, 31), rule: .every(2, .month))
        #expect(!ScheduleCalendar.isShortened(Fix.day(2027, 4, 30), of: everyTwo))
        #expect(ScheduleCalendar.isShortened(Fix.day(2027, 9, 30), of: everyTwo))
        // A month before the start isn't on the rule.
        #expect(!ScheduleCalendar.isShortened(Fix.day(2026, 11, 30), of: Fix.rent(start: Fix.day(2027, 1, 31))))
    }

    @Test("D373: Starts moved from the 30th to the 31st keeps 30 Sep overdue, without the note")
    func keptMonthEndAfterStartsEdit() throws {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let rent = Fix.rent(start: Fix.day(2026, 7, 30), automatic: false)
        try repository.useCases().save(rent)
        repository.now = Fix.date(2026, 10, 20)
        var edited = try #require(repository.snapshot.scheduledItems.first { $0.id == rent.id })
        edited.startDay = Fix.day(2026, 8, 31)
        try repository.useCases().save(edited)
        let board = try repository.useCases().listing().board
        let kept = try #require(board.overdue.first { $0.day == Fix.day(2026, 9, 30) })
        #expect(kept.item.startDay == Fix.day(2026, 8, 31))
        #expect(!ScheduleCalendar.isShortened(kept.day, of: kept.item))
        // The new rule's own 30 Nov is moved from the 31st, so it has the note.
        #expect(ScheduleCalendar.isShortened(Fix.day(2026, 11, 30), of: kept.item))
    }
}

import Foundation
import LittleOrbitDomain
import Testing

@Suite("Scheduled due days (#26, D24)")
struct ScheduleCalendarTests {
    private typealias Fix = ScheduledFixture

    private func days(_ item: ScheduledItem, _ count: Int) -> [CalendarDay] {
        ScheduleCalendar.occurrences(of: item, from: item.startDay, count: count)
    }

    @Test("A monthly item from 31 Jan 2027 falls on 28 Feb, 31 Mar, 30 Apr and 31 May, never 1 Mar")
    func monthEnd() {
        let item = Fix.rent(start: Fix.day(2027, 1, 31))
        #expect(
            days(item, 5) == [
                Fix.day(2027, 1, 31), Fix.day(2027, 2, 28), Fix.day(2027, 3, 31), Fix.day(2027, 4, 30),
                Fix.day(2027, 5, 31),
            ]
        )
        #expect(ScheduleCalendar.isShortened(Fix.day(2027, 2, 28), of: item))
        #expect(!ScheduleCalendar.isShortened(Fix.day(2027, 3, 31), of: item))
    }

    @Test("A monthly item from 30 Jan 2028 falls on 29 Feb 2028, then 30 Mar")
    func leapFebruary() {
        #expect(
            days(Fix.rent(start: Fix.day(2028, 1, 30)), 3) == [
                Fix.day(2028, 1, 30), Fix.day(2028, 2, 29), Fix.day(2028, 3, 30),
            ]
        )
    }

    @Test("A yearly item from 29 Feb 2028 falls on 28 Feb in 2029–2031 and 29 Feb in 2032")
    func leapYearly() {
        #expect(
            days(Fix.rent(start: Fix.day(2028, 2, 29), rule: .yearly), 5) == [
                Fix.day(2028, 2, 29), Fix.day(2029, 2, 28), Fix.day(2030, 2, 28), Fix.day(2031, 2, 28),
                Fix.day(2032, 2, 29),
            ]
        )
    }

    @Test("Every 2 months, every 2 weeks and daily count from the start")
    func intervals() {
        #expect(
            days(Fix.rent(start: Fix.day(2026, 12, 31), rule: .every(2, .month)), 3) == [
                Fix.day(2026, 12, 31), Fix.day(2027, 2, 28), Fix.day(2027, 4, 30),
            ]
        )
        #expect(
            days(Fix.rent(start: Fix.day(2026, 12, 25), rule: .every(2, .week)), 3) == [
                Fix.day(2026, 12, 25), Fix.day(2027, 1, 8), Fix.day(2027, 1, 22),
            ]
        )
        #expect(
            days(Fix.rent(start: Fix.day(2028, 2, 28), rule: .daily), 3) == [
                Fix.day(2028, 2, 28), Fix.day(2028, 2, 29), Fix.day(2028, 3, 1),
            ]
        )
    }

    @Test("S24: a daily item across both DST changes in London has every day once")
    func dailyAcrossDST() throws {
        var item = Fix.rent(start: Fix.day(2027, 3, 26), rule: .daily)
        item.timeZoneID = "Europe/London"
        let march = ScheduleCalendar.occurrences(of: item, through: Fix.day(2027, 3, 30))
        #expect(march == (26...30).map { Fix.day(2027, 3, $0) })
        item.startDay = Fix.day(2027, 10, 29)
        let october = ScheduleCalendar.occurrences(of: item, through: Fix.day(2027, 11, 2))
        #expect(october == [29, 30, 31].map { Fix.day(2027, 10, $0) } + [1, 2].map { Fix.day(2027, 11, $0) })
        // Each occurrence's transaction is dated on its own day in the item's zone, DST or not.
        for day in march + october {
            let transaction = try LedgerBook.scheduledTransaction(
                for: item,
                occurrence: day,
                postedOn: day,
                now: Fix.created,
            )
            #expect(TransactionCalendar.ownDay(of: transaction.date, timeZoneID: "Europe/London") == day)
        }
    }

    @Test("S79: an end date is included, and nothing falls after it")
    func endIncluded() {
        let item = Fix.transfer(start: Fix.day(2026, 11, 5), end: Fix.day(2027, 10, 5))
        let all = ScheduleCalendar.occurrences(of: item, through: Fix.day(2030, 1, 1))
        #expect(all.count == 12)
        #expect(all.first == Fix.day(2026, 11, 5))
        #expect(all.last == Fix.day(2027, 10, 5))
    }

    @Test("A one-off item has one occurrence")
    func oneOff() {
        let item = Fix.rent(start: Fix.day(2026, 11, 1), rule: .never)
        #expect(ScheduleCalendar.occurrences(of: item, through: Fix.day(2030, 1, 1)) == [Fix.day(2026, 11, 1)])
    }

    @Test("Occurrence keys are stable for an item and day, and differ for another day, item or record")
    func keys() {
        let id = UUID(uuidString: "5C000000-0000-4000-8000-0000000000AA")!
        let day = Fix.day(2026, 11, 1)
        #expect(ScheduledKey.transactionID(item: id, day: day) == ScheduledKey.transactionID(item: id, day: day))
        #expect(
            ScheduledKey.transactionID(item: id, day: day)
                != ScheduledKey.transactionID(item: id, day: Fix.day(2026, 12, 1))
        )
        #expect(ScheduledKey.transactionID(item: id, day: day) != ScheduledKey.transactionID(item: UUID(), day: day))
        #expect(ScheduledKey.transactionID(item: id, day: day) != ScheduledKey.occurrenceID(item: id, day: day))
    }
}

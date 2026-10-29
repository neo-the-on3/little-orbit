import Foundation
import Testing

@testable import LittleOrbitDomain

/// #316 review: the period check is built once per walk, so a walk looks at each record a bounded number of times,
/// not once per walked day. Counting record looks, not time, keeps this exact on any machine. Made-up data: Cleaner
/// €60.00 weekly on Mondays for 10 years, every week paid.
@Suite("A walk's period check grows with the history, not its square (#316 review)")
struct ScheduledWalkCostTests {
    private static let zone = "Asia/Kolkata"

    private static func cleaner(years: Int) -> ScheduledItem {
        let start = CalendarDay(year: 2026 - years, month: 10, day: 19)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        let created = calendar.date(from: DateComponents(year: start.year, month: 10, day: 1, hour: 10))!
        var item = ScheduledItem(
            type: .expense,
            amount: 60,
            accountID: UUID(),
            details: "Cleaner",
            startDay: start,
            repeatRule: .weekly,
            processesAutomatically: true,
            timeZoneID: zone,
            createdAt: created,
        )
        let today = CalendarDay(year: 2026, month: 10, day: 20)
        var index = 0
        while let day = ScheduleCalendar.occurrence(index, from: start, repeating: .weekly), day < today {
            item.occurrences.append(ScheduledOccurrence(id: UUID(), day: day, outcome: .posted, createdAt: created))
            index += 1
        }
        return item
    }

    @Test(
        "10 years weekly: one walk looks at each record once, and once at each walked day without one",
        arguments: [1, 10],
    )
    func walkLooksAreLinear(years: Int) {
        let item = Self.cleaner(years: years)
        let recorded = Set(item.occurrences.map(\.day))
        var walked = 0
        var walkedWithout = 0
        let looks = ScheduleCalendar.walk(item) { day in
            walked += 1
            walkedWithout += recorded.contains(day) ? 0 : 1
            return day < CalendarDay(year: 2027, month: 1, day: 1)
        }
        #expect(walked > recorded.count && walkedWithout > 0)
        // The set is built once from the records, and each walked day without a record of its own is one lookup, so
        // a check that scans the records per day, or builds the set per day, gives another count.
        #expect(
            looks == recorded.count + walkedWithout,
            "\(looks) looks for \(recorded.count) records, \(walked) days",
        )
    }
}

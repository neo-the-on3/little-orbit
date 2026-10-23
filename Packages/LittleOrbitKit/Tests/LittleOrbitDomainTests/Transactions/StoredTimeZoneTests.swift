import Foundation
import LittleOrbitDomain
import Testing

/// One fallback for a stored zone ID that isn't recognised: UTC, wherever a record's own day is read (#133).
@Suite("A record's stored zone, with UTC for one that isn't recognised")
struct StoredTimeZoneTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    static let utc = TimeZone(identifier: "UTC")!

    @Test("A recognised zone is used as it is; an unknown or empty ID reads as UTC", arguments: ["Not/AZone", ""])
    func fallback(unknown: String) {
        #expect(TransactionCalendar.storedTimeZone("Europe/London") == TimeZone(identifier: "Europe/London"))
        #expect(TransactionCalendar.storedTimeZone(unknown) == Self.utc)
    }

    @Test("The own day of a record with an unknown zone is its UTC day, in lists and refund dating too")
    func ownDayEverywhere() {
        // 10 Oct 2026 21:00 UTC is 11 Oct 02:30 in Kolkata.
        let date = F.date(2026, 10, 10, 21, zone: "UTC")
        var expense = F.expense(500, on: date)
        expense.timeZoneID = "Not/AZone"
        #expect(TransactionCalendar.ownDay(of: date, timeZoneID: "Not/AZone") == F.day(2026, 10, 10))
        #expect(TransactionCalendar.ownDay(of: date, timeZoneID: F.india) == F.day(2026, 10, 11))
        #expect(TransactionTiming.day(of: expense) == F.day(2026, 10, 10))
        #expect(TransactionCalendar.groups([expense]).map(\.day) == [F.day(2026, 10, 10)], "Listed, never dropped")

        var refund = F.expense(100, on: F.date(2026, 10, 10, 23, zone: "UTC"))
        refund.timeZoneID = ""
        #expect(!RefundDating.isOriginal(expense, datedAfter: refund), "Both on 10 Oct in UTC")
        refund.date = F.date(2026, 10, 9, 23, zone: "UTC")
        #expect(RefundDating.isOriginal(expense, datedAfter: refund))
    }
}

import Foundation
import LittleOrbitDomain
import Testing

/// Moving a record's date to a picked day in its own stored zone (#131, D230.1, D232.1). Names and dates are
/// made up.
@Suite("A picked day in the record's own zone (D230.1, D232.1)")
struct TransactionDayMoveTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    static let london = "Europe/London"
    static let kolkata = "Asia/Kolkata"

    private func moved(_ date: Date, to day: CalendarDay, in zone: String) -> Date {
        TransactionCalendar.date(date, movedTo: day, timeZoneID: zone)
    }

    @Test("E1, E4: 10 Oct 21:00 London moved to 12 Oct is 12 Oct 21:00 London, with no device zone involved")
    func crossZone() {
        let refund = F.date(2026, 10, 10, 21, zone: Self.london)
        let result = moved(refund, to: F.day(2026, 10, 12), in: Self.london)
        #expect(result == F.date(2026, 10, 12, 21, zone: Self.london))
        #expect(TransactionCalendar.calendarDay(of: result, timeZoneID: Self.london) == F.day(2026, 10, 12))
        // On an IST device the same moment already reads 13 Oct 01:30, which is why the day is set in London.
        #expect(TransactionCalendar.calendarDay(of: result, timeZoneID: Self.kolkata) == F.day(2026, 10, 13))
    }

    @Test("E1 reverse: 9 Oct 23:00 Kolkata moved to 12 Oct is 12 Oct 23:00 Kolkata")
    func reverseCrossZone() {
        let expense = F.date(2026, 10, 9, 23, zone: Self.kolkata)
        let result = moved(expense, to: F.day(2026, 10, 12), in: Self.kolkata)
        #expect(result == F.date(2026, 10, 12, 23, zone: Self.kolkata))
        #expect(TransactionCalendar.calendarDay(of: result, timeZoneID: Self.london) == F.day(2026, 10, 12))
    }

    @Test("E3: same zone, 18 Oct 09:15 Kolkata moved to 20 Oct is 20 Oct 09:15 Kolkata")
    func sameZone() {
        let bakery = F.date(2026, 10, 18, 9, 15, zone: Self.kolkata)
        #expect(moved(bakery, to: F.day(2026, 10, 20), in: Self.kolkata) == F.date(2026, 10, 20, 9, 15))
    }

    @Test("E5: 01:30 London moved to 29 Mar 2026, inside the gap, is 02:00 BST, the first valid time after it")
    func springGap() {
        let streamBox = F.date(2026, 3, 20, 1, 30, zone: Self.london)
        let result = moved(streamBox, to: F.day(2026, 3, 29), in: Self.london)
        #expect(result == F.date(2026, 3, 29, 1, 0, zone: "UTC"))
        #expect(result == F.date(2026, 3, 29, 2, 0, zone: Self.london))
        #expect(TransactionCalendar.calendarDay(of: result, timeZoneID: Self.london) == F.day(2026, 3, 29))
    }

    @Test("E9: 18 Oct 01:30 London moved to 25 Oct 2026, a repeated hour, is the first 01:30 (BST, 00:30 UTC)")
    func repeatedHour() {
        let early = F.date(2026, 10, 18, 1, 30, zone: Self.london)
        let result = moved(early, to: F.day(2026, 10, 25), in: Self.london)
        #expect(result == F.date(2026, 10, 25, 0, 30, zone: "UTC"))
        #expect(TransactionCalendar.calendarDay(of: result, timeZoneID: Self.london) == F.day(2026, 10, 25))
    }

    @Test("E9: the second 01:30 (GMT) moved to another day keeps 01:30 there")
    func secondOccurrenceMoved() {
        let second = F.date(2026, 10, 25, 1, 30, zone: "UTC")
        let result = moved(second, to: F.day(2026, 10, 27), in: Self.london)
        #expect(result == F.date(2026, 10, 27, 1, 30, zone: Self.london))
    }

    @Test("A time after the gap on the gap day is kept exactly")
    func afterGapKept() {
        let evening = F.date(2026, 3, 20, 21, zone: Self.london)
        let result = moved(evening, to: F.day(2026, 3, 29), in: Self.london)
        #expect(result == F.date(2026, 3, 29, 21, zone: Self.london))
    }

    @Test("Midnight stays midnight, and a fraction of a second is kept")
    func midnightAndFraction() {
        let midnight = F.date(2026, 10, 10, 0, zone: Self.london).addingTimeInterval(0.25)
        let result = moved(midnight, to: F.day(2026, 10, 12), in: Self.london)
        #expect(result == F.date(2026, 10, 12, 0, zone: Self.london).addingTimeInterval(0.25))
    }

    @Test("Already on the picked day: the same moment comes back, so nothing is written")
    func sameDayUnchanged() {
        let refund = F.date(2026, 10, 10, 21, 7, zone: Self.london).addingTimeInterval(0.5)
        #expect(moved(refund, to: F.day(2026, 10, 10), in: Self.london) == refund)
    }

    @Test("An unknown or empty zone ID moves the day in UTC, so a pick always lands", arguments: ["Not/AZone", ""])
    func unknownZone(zoneID: String) {
        let restored = F.date(2026, 10, 10, 21, zone: "UTC")
        let result = moved(restored, to: F.day(2026, 10, 12), in: zoneID)
        #expect(result == F.date(2026, 10, 12, 21, zone: "UTC"))
        #expect(TransactionCalendar.ownDay(of: result, timeZoneID: zoneID) == F.day(2026, 10, 12))
    }

    @Test("Midnight gap (America/Santiago, 6 Sep 2026): 00:30 lands at 01:00 on the picked day, never the day before")
    func midnightGap() {
        let santiago = "America/Santiago"
        for (hour, minute) in [(0, 0), (0, 30)] {
            let early = F.date(2026, 8, 30, hour, minute, zone: santiago)
            let result = moved(early, to: F.day(2026, 9, 6), in: santiago)
            #expect(TransactionCalendar.ownDay(of: result, timeZoneID: santiago) == F.day(2026, 9, 6))
            #expect(result == F.date(2026, 9, 6, 1, 0, zone: santiago))
        }
        let late = F.date(2026, 8, 30, 23, 30, zone: santiago)
        #expect(moved(late, to: F.day(2026, 9, 6), in: santiago) == F.date(2026, 9, 6, 23, 30, zone: santiago))
    }

    @Test("Every day of 2026 in zones with daylight saving lands on the picked day")
    func alwaysOnPickedDay() {
        for zone in ["America/Santiago", "Europe/London", "America/New_York", "Australia/Lord_Howe", "Asia/Kolkata"] {
            for hour in [0, 1, 2, 23] {
                let source = F.date(2025, 12, 31, hour, 30, zone: zone)
                var day = F.date(2026, 1, 1, 12, zone: zone)
                for _ in 0..<365 {
                    let picked = TransactionCalendar.ownDay(of: day, timeZoneID: zone)
                    let result = moved(source, to: picked, in: zone)
                    #expect(TransactionCalendar.ownDay(of: result, timeZoneID: zone) == picked, "\(zone) \(picked)")
                    day = day.addingTimeInterval(86_400)
                }
            }
        }
    }

    @Test("The use case forwards to the calendar")
    @MainActor
    func useCase() {
        let dates = DefaultTransactionDateUseCase()
        let refund = F.date(2026, 10, 10, 21, zone: Self.london)
        #expect(dates.day(of: refund, timeZoneID: Self.london) == F.day(2026, 10, 10))
        #expect(dates.day(of: refund, timeZoneID: Self.kolkata) == F.day(2026, 10, 11))
        #expect(
            dates.noon(on: F.day(2026, 10, 10), timeZoneID: Self.kolkata)
                == F.date(2026, 10, 10, 12, zone: Self.kolkata)
        )
        #expect(
            dates.noon(on: F.day(2026, 10, 10), timeZoneID: "Not/AZone") == F.date(2026, 10, 10, 12, zone: "UTC")
        )
        #expect(dates.storedTimeZone("") == TimeZone(identifier: "UTC"))
        #expect(dates.day(of: refund, timeZoneID: "Not/AZone") == F.day(2026, 10, 10))
        let moved = dates.date(refund, movedTo: F.day(2026, 10, 12), timeZoneID: Self.london)
        #expect(moved == F.date(2026, 10, 12, 21, zone: Self.london))
    }
}

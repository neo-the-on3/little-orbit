import Foundation
import LittleOrbitDomain
import Testing

/// A bulk Date change: each row moves to the picked day in its own zone, and refunds and their expenses keep
/// their order (#34; D222.5, D225.4, D225.5, D227.1, D229, D230.2, D232; P20, P26–P28). Names are made up.
@Suite("Bulk edit: Date")
struct BulkEditDateTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    static let kolkata = "Asia/Kolkata"
    static let london = "Europe/London"
    static let newYork = "America/New_York"

    private let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
    private let travel = Account(name: "Travel Card", type: .creditCard, currencyCode: "USD")

    private func expense(_ date: Date, zone: String = kolkata) -> Transaction {
        Transaction(type: .expense, amount: 1_000, date: date, timeZoneID: zone, accountID: savings.id)
    }

    private func refund(of expense: Transaction?, _ date: Date, zone: String = kolkata) -> Transaction {
        Transaction(
            type: .income,
            amount: 300,
            date: date,
            timeZoneID: zone,
            accountID: savings.id,
            refundOfID: expense?.id,
            isRefund: true,
        )
    }

    private func moving(
        _ selection: [Transaction],
        to day: CalendarDay,
        ledger: [Transaction] = [],
        account: UUID? = nil,
    ) throws(BulkEditRejection) -> [Transaction] {
        var changes = BulkEditChanges()
        changes.date = day
        changes.accountID = account
        return try BulkEditRules.apply(changes, to: selection, accounts: [savings, travel], ledger: ledger)
    }

    private func rejection(_ body: () throws(BulkEditRejection) -> [Transaction]) -> BulkEditRejection? {
        do {
            _ = try body()
            return nil
        } catch {
            return error
        }
    }

    @Test("P28: each row keeps its zone and time of day; a row already on the day is unchanged (D230.2)")
    func ownZoneAndTime() throws {
        let refund = refund(of: nil, F.date(2026, 10, 10, 21, 0, zone: Self.london), zone: Self.london)
        let bakery = expense(F.date(2026, 10, 18, 9, 15, zone: Self.kolkata))
        let already = expense(F.date(2026, 10, 25, 7, 30, zone: Self.newYork), zone: Self.newYork)
        let result = try moving([refund, bakery, already], to: F.day(2026, 10, 25))
        #expect(result[0].date == F.date(2026, 10, 25, 21, 0, zone: Self.london))
        #expect(result[0].timeZoneID == Self.london)
        #expect(result[1].date == F.date(2026, 10, 25, 9, 15, zone: Self.kolkata))
        #expect(result[1].timeZoneID == Self.kolkata)
        #expect(result[2] == already)
    }

    @Test("P28: a daylight-saving gap gives the first valid time after it (D230.2)")
    func daylightGap() throws {
        // New York's clocks jump from 02:00 to 03:00 on 8 Mar 2026, so 02:30 doesn't exist that day.
        let row = expense(F.date(2026, 3, 1, 2, 30, zone: Self.newYork), zone: Self.newYork)
        let result = try moving([row], to: F.day(2026, 3, 8))
        #expect(result[0].date == F.date(2026, 3, 8, 3, 0, zone: Self.newYork))
        #expect(result[0].timeZoneID == Self.newYork)
    }

    @Test("D232.1: a repeated hour takes its first occurrence, the same moment the editor picks")
    func repeatedHour() throws {
        // New York's clocks go back from 02:00 to 01:00 on 1 Nov 2026, so 01:30 happens twice.
        let row = expense(F.date(2026, 10, 20, 1, 30, zone: Self.newYork), zone: Self.newYork)
        let result = try moving([row], to: F.day(2026, 11, 1))
        let first = try #require(ISO8601DateFormatter().date(from: "2026-11-01T05:30:00Z"))
        #expect(result[0].date == first)
        #expect(
            result[0].date
                == TransactionCalendar.date(row.date, movedTo: F.day(2026, 11, 1), timeZoneID: Self.newYork)
        )
    }

    @Test("An unknown or empty zone ID moves the row in UTC and is kept as it is", arguments: ["Mars/Olympus", ""])
    func unknownZone(_ zone: String) throws {
        let row = expense(F.date(2026, 10, 10, 8, 0, zone: "UTC"), zone: zone)
        let result = try moving([row], to: F.day(2026, 10, 12))
        #expect(result[0].date == F.date(2026, 10, 12, 8, 0, zone: "UTC"))
        #expect(result[0].timeZoneID == zone)
    }

    @Test("P20: an expense moved after its refund saves nothing and names the refund's day (D222.5, D225.5)")
    func expenseAfterRefund() {
        let shopping = expense(F.date(2026, 10, 17))
        let refund = refund(of: shopping, F.date(2026, 10, 20))
        let other = expense(F.date(2026, 10, 18))
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([shopping, other], to: F.day(2026, 10, 25), ledger: [shopping, refund, other])
            } == .expenseAfterRefunds(count: 1, earliestRefund: F.day(2026, 10, 20))
        )
        // On the refund's day it saves (D112: on or after).
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([shopping], to: F.day(2026, 10, 20), ledger: [shopping, refund])
            } == nil
        )
    }

    @Test("D225.5: several expenses count, and the earliest refund decides")
    func severalExpenses() {
        let first = expense(F.date(2026, 10, 10))
        let second = expense(F.date(2026, 10, 11))
        let ledger = [
            first, second, refund(of: first, F.date(2026, 10, 22)), refund(of: first, F.date(2026, 10, 21)),
            refund(of: second, F.date(2026, 10, 20)),
        ]
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([first, second], to: F.day(2026, 10, 25), ledger: ledger)
            } == .expenseAfterRefunds(count: 2, earliestRefund: F.day(2026, 10, 20))
        )
    }

    @Test("D225.4: refunds moved before their expense count, and the latest expense decides")
    func refundsBeforeExpense() {
        let early = expense(F.date(2026, 10, 15))
        let late = expense(F.date(2026, 10, 17))
        let refunds = [refund(of: early, F.date(2026, 10, 20)), refund(of: late, F.date(2026, 10, 20))]
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving(refunds, to: F.day(2026, 10, 12), ledger: [early, late] + refunds)
            } == .refundBeforeExpense(count: 2, latestExpense: F.day(2026, 10, 17))
        )
        // Moving a refund and its expense together to one day saves.
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([early, refunds[0]], to: F.day(2026, 10, 12), ledger: [early, late] + refunds)
            } == nil
        )
    }

    @Test("B2: refunds are matched to their own expense; a deleted refund doesn't count")
    func refundsGroupedByExpense() {
        let first = expense(F.date(2026, 10, 10))
        let second = expense(F.date(2026, 10, 11))
        var deleted = refund(of: second, F.date(2026, 10, 12))
        deleted.deletedAt = F.date(2026, 10, 13)
        let ledger = [first, second, refund(of: first, F.date(2026, 10, 30)), deleted]
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([first, second], to: F.day(2026, 10, 25), ledger: ledger)
            } == nil
        )
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([first, second], to: F.day(2026, 10, 31), ledger: ledger)
            } == .expenseAfterRefunds(count: 1, earliestRefund: F.day(2026, 10, 30))
        )
    }

    @Test("An orphaned refund has no expense to stay after")
    func orphanedRefund() {
        let orphan = refund(of: nil, F.date(2026, 10, 20))
        #expect(rejection { () throws(BulkEditRejection) in try moving([orphan], to: F.day(2026, 9, 1)) } == nil)
    }

    @Test("D227.1: Date is checked before Account, and an expense after its refunds before a refund before its expense")
    func order() {
        let shopping = expense(F.date(2026, 10, 17))
        let shoppingRefund = refund(of: shopping, F.date(2026, 10, 20))
        let other = expense(F.date(2026, 10, 19))
        let otherRefund = refund(of: other, F.date(2026, 10, 19))
        let ledger = [shopping, shoppingRefund, other, otherRefund]
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([shopping, otherRefund], to: F.day(2026, 10, 25), ledger: ledger, account: travel.id)
            } == .expenseAfterRefunds(count: 1, earliestRefund: F.day(2026, 10, 20))
        )
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([otherRefund], to: F.day(2026, 10, 1), ledger: ledger, account: travel.id)
            } == .refundBeforeExpense(count: 1, latestExpense: F.day(2026, 10, 19))
        )
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([other], to: F.day(2026, 10, 19), ledger: ledger, account: travel.id)
            } == .otherCurrency(count: 1, currencyCode: "INR", accountID: travel.id)
        )
    }

    @Test("P26: days compare in each record's own zone, never by the moment")
    func crossZone() {
        // Trailhead Sports at 10 Oct 01:00 in Kolkata shows 10 Oct.
        let trailhead = expense(F.date(2026, 10, 10, 1, 0, zone: Self.kolkata))
        let trailheadRefund = refund(of: trailhead, F.date(2026, 10, 12, 21, 0, zone: Self.london), zone: Self.london)
        // To 9 Oct at 21:00 London: a later moment than the expense, but an earlier day.
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([trailheadRefund], to: F.day(2026, 10, 9), ledger: [trailhead, trailheadRefund])
            } == .refundBeforeExpense(count: 1, latestExpense: F.day(2026, 10, 10))
        )
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([trailheadRefund], to: F.day(2026, 10, 10), ledger: [trailhead, trailheadRefund])
            } == nil
        )
        // The reverse: an expense at 9 Oct 23:00 London, and a refund at 10 Oct 02:00 Kolkata, an earlier moment.
        let london = expense(F.date(2026, 10, 1, 23, 0, zone: Self.london), zone: Self.london)
        let early = refund(of: london, F.date(2026, 10, 10, 2, 0, zone: Self.kolkata))
        #expect(
            rejection { () throws(BulkEditRejection) in
                try moving([london], to: F.day(2026, 10, 9), ledger: [london, early])
            } == nil
        )
    }

    @Test(
        "P27: a bulk Date change, the refund form and Undo's check agree on the same records",
        arguments: [kolkata, london, newYork],
    )
    func sameDays(_ refundZone: String) {
        let trailhead = expense(F.date(2026, 10, 10, 1, 0, zone: Self.kolkata))
        for refundDay in [9, 10, 11] {
            let stored = refund(of: trailhead, F.date(2026, 10, 12, 21, 0, zone: refundZone), zone: refundZone)
            var moved = stored
            moved.date = TransactionCalendar.date(
                stored.date,
                movedTo: F.day(2026, 10, refundDay),
                timeZoneID: refundZone,
            )
            let undoSays = RefundDating.isOriginal(trailhead, datedAfter: moved)
            let bulkSays = rejection { () throws(BulkEditRejection) in
                try moving([stored], to: F.day(2026, 10, refundDay), ledger: [trailhead, stored])
            }
            let formSays = RefundPlan.issues(of: moved, for: trailhead, in: LedgerSnapshot(accounts: [savings]))
            #expect(undoSays == (refundDay < 10))
            #expect((bulkSays != nil) == undoSays)
            #expect(formSays.contains(.dateBeforeOriginal(F.day(2026, 10, 10))) == undoSays)
        }
    }
}

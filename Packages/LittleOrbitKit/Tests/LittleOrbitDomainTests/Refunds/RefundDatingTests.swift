import Foundation
import LittleOrbitDomain
import Testing

/// `RefundDating`: the one 'dated after' comparison that D224.2's stale check uses now and #34's D112 save
/// check will use later.
@Suite("Refund dating (#55, D224.2, D112)")
struct RefundDatingTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = RefundFixture  // swiftlint:disable:this type_name

    @Test("The same day isn't after, even later in the day; the next day is")
    func sameZone() {
        let refund = R.refund(2_000, of: nil, on: F.date(2026, 10, 10, 9))
        #expect(!RefundDating.isOriginal(R.expense(5_000, on: F.date(2026, 10, 10, 23)), datedAfter: refund))
        #expect(!RefundDating.isOriginal(R.expense(5_000, on: F.date(2026, 10, 9, 23)), datedAfter: refund))
        #expect(RefundDating.isOriginal(R.expense(5_000, on: F.date(2026, 10, 11, 0, 30)), datedAfter: refund))
    }

    /// Tech Architect's example: the refund is the later moment but has the earlier day in its own zone.
    @Test("D229.1: in different zones, each record is read on its own day in its own zone")
    func differentZones() {
        let expense = R.expense(5_000, on: F.date(2026, 10, 10, 1))
        let london = "Europe/London"
        let refund = R.refund(2_000, of: expense, on: F.date(2026, 10, 9, 21, zone: london), zone: london)
        #expect(refund.date > expense.date)
        #expect(RefundDating.isOriginal(expense, datedAfter: refund))
    }
}

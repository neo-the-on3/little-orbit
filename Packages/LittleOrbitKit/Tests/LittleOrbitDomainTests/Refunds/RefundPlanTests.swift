import Foundation
import LittleOrbitDomain
import Testing

/// The refund form's rules for a non-split expense (#34, D33, D35, D65, D97.4). Fixture F34, made up.
@Suite("Refund plan")
struct RefundPlanTests {
    typealias F = SplitsRefundsFixture  // swiftlint:disable:this type_name

    private let now = F.date(10, 23)

    private func shoppingWithRefund() throws -> (SplitsRefundsFixture, Transaction) {
        var fixture = try SplitsRefundsFixture()
        let expense = try fixture.expense(1_000, in: fixture.shopping, on: F.date(10, 17))
        try fixture.refund(300, of: expense, in: fixture.shopping, on: F.date(10, 18))
        return (fixture, expense)
    }

    @Test("Refund opens with ₹700, today, Shopping and Everyday Savings (S14)")
    func newRefundPrefill() throws {
        let (fixture, expense) = try shoppingWithRefund()
        let refund = try #require(RefundPlan.newRefund(of: expense, in: fixture.snapshot, now: now))
        #expect(refund.amount == 700)
        #expect(refund.date == now)
        #expect(refund.categoryID == fixture.shopping.id)
        #expect(refund.accountID == fixture.savings.id)
        #expect(refund.type == .income)
        #expect(refund.isRefund && refund.refundOfID == expense.id)
        #expect(RefundPlan.issues(of: refund, for: expense, in: fixture.snapshot).isEmpty)
    }

    @Test("₹701 is blocked with ₹700 refundable; after ₹700 nothing is refundable (S16)")
    func cap() throws {
        var (fixture, expense) = try shoppingWithRefund()
        var refund = try #require(RefundPlan.newRefund(of: expense, in: fixture.snapshot, now: now))
        refund.amount = 701
        #expect(RefundPlan.issues(of: refund, for: expense, in: fixture.snapshot) == [.exceedsRefundable(700)])
        try fixture.refund(700, of: expense, in: fixture.shopping, on: now)
        let next = try #require(RefundPlan.newRefund(of: expense, in: fixture.snapshot, now: now))
        #expect(next.amount == 0)
        #expect(RefundPlan.issues(of: next, for: expense, in: fixture.snapshot) == [.nothingRefundable])
    }

    @Test("Editing a refund counts its new amount, not old plus new")
    func editingCountsTheNewAmount() throws {
        let (fixture, expense) = try shoppingWithRefund()
        var existing = try #require(fixture.snapshot.transactions.first { $0.refundOfID == expense.id })
        existing.amount = 1_000
        #expect(RefundPlan.issues(of: existing, for: expense, in: fixture.snapshot).isEmpty)
        existing.amount = 1_001
        #expect(RefundPlan.issues(of: existing, for: expense, in: fixture.snapshot) == [.exceedsRefundable(1_000)])
    }

    @Test("Another INR account saves; a USD account is blocked (D33, S15)")
    func currency() throws {
        let (fixture, expense) = try shoppingWithRefund()
        var refund = try #require(RefundPlan.newRefund(of: expense, in: fixture.snapshot, now: now))
        refund.accountID = fixture.wallet.id
        #expect(RefundPlan.issues(of: refund, for: expense, in: fixture.snapshot).isEmpty)
        refund.accountID = fixture.travel.id
        #expect(RefundPlan.issues(of: refund, for: expense, in: fixture.snapshot) == [.currencyMismatch])
    }

    @Test("A refund dated before its expense is blocked with the expense's date; the same day and later save (S49)")
    func refundDate() throws {
        let (fixture, expense) = try shoppingWithRefund()
        var refund = try #require(RefundPlan.newRefund(of: expense, in: fixture.snapshot, now: now))
        refund.date = F.date(10, 16)
        #expect(
            RefundPlan.issues(of: refund, for: expense, in: fixture.snapshot)
                == [.dateBeforeOriginal(CalendarDay(year: 2026, month: 10, day: 17))]
        )
        refund.date = F.date(10, 17)
        #expect(RefundPlan.issues(of: refund, for: expense, in: fixture.snapshot).isEmpty)
    }

    @Test("Refund isn't offered for income, transfers, refunds, or (yet) a split expense")
    func notOffered() throws {
        var fixture = try SplitsRefundsFixture()
        let split = try fixture.split([(fixture.groceries, 600), (fixture.household, 400)], on: F.date(10, 20))
        #expect(RefundPlan.newRefund(of: split, in: fixture.snapshot, now: now) == nil)
        let income = Transaction(type: .income, amount: 10, accountID: fixture.savings.id)
        #expect(RefundPlan.newRefund(of: income, in: fixture.snapshot, now: now) == nil)
        let (withRefund, expense) = try shoppingWithRefund()
        let refund = try #require(withRefund.snapshot.transactions.first { $0.refundOfID == expense.id })
        #expect(RefundPlan.newRefund(of: refund, in: withRefund.snapshot, now: now) == nil)
    }

    private struct Pair {
        let fixture: SplitsRefundsFixture
        let expense: Transaction
        let refund: Transaction
    }

    /// Expense and refund with their own stored zones, for P26.
    private func pair(
        expenseAt expenseDate: Date,
        in expenseZone: String,
        refundAt refundDate: Date,
        in refundZone: String,
    ) throws -> Pair {
        var fixture = try SplitsRefundsFixture()
        var expense = try fixture.expense(1_000, in: fixture.shopping, on: expenseDate)
        expense.timeZoneID = expenseZone
        var refund = try #require(RefundPlan.newRefund(of: expense, in: fixture.snapshot, now: now))
        refund.date = refundDate
        refund.timeZoneID = refundZone
        return Pair(fixture: fixture, expense: expense, refund: refund)
    }

    @Test("P26: a refund on an earlier own day is blocked, naming the expense's own day (D229.1)")
    func crossZoneEarlierDay() throws {
        let found = try pair(
            expenseAt: TransactionFixture.date(2026, 10, 10, 1, 0, zone: "Asia/Kolkata"),
            in: "Asia/Kolkata",
            refundAt: TransactionFixture.date(2026, 10, 9, 21, 0, zone: "Europe/London"),
            in: "Europe/London",
        )
        let (fixture, expense, refund) = (found.fixture, found.expense, found.refund)
        #expect(
            RefundPlan.issues(of: refund, for: expense, in: fixture.snapshot)
                == [.dateBeforeOriginal(CalendarDay(year: 2026, month: 10, day: 10))]
        )
        var picked = refund
        picked.date = TransactionCalendar.date(
            refund.date,
            movedTo: CalendarDay(year: 2026, month: 10, day: 10),
            timeZoneID: refund.timeZoneID,
        )
        #expect(RefundPlan.issues(of: picked, for: expense, in: fixture.snapshot).isEmpty)
    }

    @Test("P26: an earlier moment on a later own day saves, and so does the same own day")
    func crossZoneSaves() throws {
        let reverse = try pair(
            expenseAt: TransactionFixture.date(2026, 10, 9, 23, 0, zone: "Europe/London"),
            in: "Europe/London",
            refundAt: TransactionFixture.date(2026, 10, 10, 2, 0, zone: "Asia/Kolkata"),
            in: "Asia/Kolkata",
        )
        #expect(RefundPlan.issues(of: reverse.refund, for: reverse.expense, in: reverse.fixture.snapshot).isEmpty)
        let sameDay = try pair(
            expenseAt: TransactionFixture.date(2026, 10, 10, 20, 0, zone: "America/Los_Angeles"),
            in: "America/Los_Angeles",
            refundAt: TransactionFixture.date(2026, 10, 10, 9, 0, zone: "Asia/Kolkata"),
            in: "Asia/Kolkata",
        )
        #expect(RefundPlan.issues(of: sameDay.refund, for: sameDay.expense, in: sameDay.fixture.snapshot).isEmpty)
    }

    @Test("An unknown or empty zone ID reads as UTC, never skipping the check", arguments: ["Mars/Olympus", ""])
    func unknownZone(_ zone: String) throws {
        let found = try pair(
            expenseAt: TransactionFixture.date(2026, 10, 10, 1, 0, zone: "UTC"),
            in: zone,
            refundAt: TransactionFixture.date(2026, 10, 9, 23, 0, zone: "UTC"),
            in: zone,
        )
        let (fixture, expense, refund) = (found.fixture, found.expense, found.refund)
        #expect(
            RefundPlan.issues(of: refund, for: expense, in: fixture.snapshot)
                == [.dateBeforeOriginal(CalendarDay(year: 2026, month: 10, day: 10))]
        )
    }
}

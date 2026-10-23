import Foundation
import LittleOrbitDomain
import Testing

/// Refunds in category spending for budgets (#25) and reports (#27): a refund lowers its category in the
/// period it's dated, by its stored time zone, and is never income (#55 AC 2; D19, D33.2, D33.3, D35.3, D35.4).
@Suite("Refunds in category spending (#55)")
struct RefundSpendingTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = RefundFixture  // swiftlint:disable:this type_name

    private let october = (F.day(2026, 10, 1), F.day(2026, 10, 31))
    private let november = (F.day(2026, 11, 1), F.day(2026, 11, 30))

    private func spending(
        _ snapshot: LedgerSnapshot,
        _ period: (CalendarDay, CalendarDay),
        category: UUID? = R.groceriesID,
        currency: String = "INR",
    ) -> Decimal {
        CategorySpending.spending(in: snapshot, from: period.0, through: period.1)[
            CategoryCurrency(categoryID: category, currencyCode: currency)
        ] ?? 0
    }

    private func income(_ snapshot: LedgerSnapshot, _ period: (CalendarDay, CalendarDay)) -> Decimal {
        CategorySpending.income(in: snapshot, from: period.0, through: period.1).values.reduce(0, +)
    }

    @Test("AC2, v1 Happy 2–3: a ₹20 refund of a ₹50 expense leaves ₹30 spent and isn't income")
    func refundLowersSpending() throws {
        let expense = R.expense(50)
        let snapshot = try R.saving([expense, R.refund(20, of: expense)])
        #expect(spending(snapshot, october) == 30)
        #expect(income(snapshot, october) == 0)
        let spent = CategorySpending.spent(
            on: [R.groceriesID],
            currencyCode: "INR",
            in: snapshot,
            from: october.0,
            through: october.1,
        )
        #expect(spent == 30)
    }

    @Test("v1 Edge 1, B1, S23: two refunds net out; a fully refunded expense is ₹0 with income unchanged")
    func severalRefunds() throws {
        let expense = R.expense(50)
        let partly = try R.saving([expense, R.refund(20, of: expense), R.refund(10, of: expense)])
        #expect(spending(partly, october) == 20)
        let full = R.expense(5_000)
        var salary = F.income(9_000, on: R.october)
        salary.categoryID = R.salaryID
        let fully = try R.saving([full, R.refund(5_000, of: full), salary])
        #expect(spending(fully, october) == 0)
        #expect(income(fully, october) == 9_000)
    }

    @Test("S20, A2b: an unlinked refund still lowers its category in its own period and isn't income")
    func orphanStillCounts() throws {
        let expense = R.expense(1_000, in: R.shoppingID)
        let saved = try R.saving([expense, R.refund(200, of: expense), R.refund(100, of: expense)])
        let deleted = try LedgerBook.deletingTransaction(id: expense.id, in: saved, now: R.october)
        #expect(spending(deleted, october, category: R.shoppingID) == -300)
        #expect(income(deleted, october) == 0)
    }

    @Test("C1 (D33.3): a refund counts in the month it's dated, not the expense's month")
    func refundInItsOwnMonth() throws {
        let expense = R.expense(5_000, on: F.date(2026, 9, 28))
        let snapshot = try R.saving([expense, R.refund(2_000, of: expense, on: F.date(2026, 10, 3))])
        #expect(spending(snapshot, (F.day(2026, 9, 1), F.day(2026, 9, 30))) == 5_000)
        #expect(spending(snapshot, october) == -2_000)
    }

    @Test("C2 (simulator rewrite): a refund at 1 Nov 00:15 IST counts in November only")
    func refundJustAfterMidnight() throws {
        let expense = R.expense(5_000)
        let refund = R.refund(
            2_000,
            of: expense,
            on: F.date(2026, 11, 1, 0, 15, zone: "Asia/Kolkata"),
            zone: "Asia/Kolkata",
        )
        let snapshot = try R.saving([expense, refund])
        #expect(spending(snapshot, october) == 5_000)
        #expect(spending(snapshot, november) == -2_000)
    }

    @Test("C2a (simulator rewrite, D35.4): the stored zone decides, whatever the device's zone is now")
    func storedZoneDecides() throws {
        let expense = R.expense(5_000)
        let refund = R.refund(
            2_000,
            of: expense,
            on: F.date(2026, 11, 1, 0, 15, zone: "Asia/Kolkata"),
            zone: "Asia/Kolkata",
        )
        let snapshot = try R.saving([expense, refund])
        // The same moment is 31 Oct 18:45 in London; nothing here reads the device's zone, so no
        // TimeZone.current can move it.
        #expect(TransactionCalendar.calendarDay(of: refund.date, timeZoneID: "Europe/London") == F.day(2026, 10, 31))
        #expect(spending(snapshot, november) == -2_000)
        #expect(spending(snapshot, october) == 5_000)
    }

    @Test("C2b (simulator rewrite): an expense and its refund each count by their own stored zone")
    func eachByItsOwnZone() throws {
        let expense = R.expense(5_000, on: F.date(2026, 10, 31, 23, 30, zone: "Asia/Kolkata"), zone: "Asia/Kolkata")
        let refund = R.refund(
            2_000,
            of: expense,
            on: F.date(2026, 10, 31, 20, 0, zone: "Europe/London"),
            zone: "Europe/London",
        )
        let snapshot = try R.saving([expense, refund])
        #expect(spending(snapshot, october) == 3_000)
        #expect(spending(snapshot, november) == 0)
    }

    @Test("C3 (D35.3): a refund alone is ₹0 spent with ₹2,000 credit, and ₹12,000 of ₹10,000 remains")
    func refundOnlyCredit() throws {
        let expense = R.expense(5_000, on: F.date(2026, 9, 20))
        let snapshot = try R.saving([expense, R.refund(2_000, of: expense, on: F.date(2026, 10, 3))])
        let net = spending(snapshot, october)
        #expect(net == -2_000)
        let figures = BudgetFigures(budget: 10_000, netSpending: net)
        #expect(figures.spent == 0)
        #expect(figures.credit == 2_000)
        #expect(figures.remaining == 12_000)
        #expect(income(snapshot, october) == 0)
    }

    @Test("C4: an expense of ₹1,500 and a refund of ₹2,000 net −₹500: ₹0 spent, ₹500 credit, ₹10,500 left")
    func netNegative() throws {
        let old = R.expense(5_000, on: F.date(2026, 9, 20))
        let snapshot = try R.saving([old, R.refund(2_000, of: old, on: F.date(2026, 10, 3)), R.expense(1_500)])
        let figures = BudgetFigures(budget: 10_000, netSpending: spending(snapshot, october))
        #expect(figures.netSpending == -500)
        #expect(figures.spent == 0)
        #expect(figures.credit == 500)
        #expect(figures.remaining == 10_500)
    }

    @Test("C7 (D35.3): with rollover on, October's ₹12,000 left makes November ₹22,000; off, ₹10,000")
    func rollover() {
        let octoberFigures = BudgetFigures(budget: 10_000, netSpending: -2_000)
        let rolledOver = BudgetFigures(budget: 10_000, netSpending: 0, carriedOver: octoberFigures.remaining)
        #expect(rolledOver.available == 22_000)
        #expect(BudgetFigures(budget: 10_000, netSpending: 0).available == 10_000)
    }

    @Test("C5: in a weekly period a refund counts in the week it's dated")
    func weeklyPeriod() throws {
        let expense = R.expense(5_000, on: F.date(2026, 10, 9))
        let snapshot = try R.saving([expense, R.refund(2_000, of: expense, on: F.date(2026, 10, 13))])
        #expect(spending(snapshot, (F.day(2026, 10, 5), F.day(2026, 10, 11))) == 5_000)
        #expect(spending(snapshot, (F.day(2026, 10, 12), F.day(2026, 10, 18))) == -2_000)
    }

    @Test("D1, D5: after the expense moves, its refund moves with it in every period; uncategorised too")
    func totalsFollowCategory() throws {
        var expense = R.expense(5_000, on: F.date(2026, 9, 28))
        let refund = R.refund(2_000, of: expense, on: F.date(2026, 10, 3))
        var snapshot = try R.saving([expense, refund])
        expense.categoryID = R.diningID
        snapshot = try LedgerBook.savingTransaction(expense, in: snapshot, now: R.october)
        #expect(spending(snapshot, october, category: R.groceriesID) == 0)
        #expect(spending(snapshot, october, category: R.diningID) == -2_000)
        expense.categoryID = nil
        snapshot = try LedgerBook.savingTransaction(expense, in: snapshot, now: R.october)
        #expect(spending(snapshot, october, category: nil) == -2_000)
        #expect(income(snapshot, october) == 0)
    }

    @Test("E2: a refund to another INR account still lowers the category")
    func otherAccount() throws {
        let expense = R.expense(5_000, account: R.cardID)
        let snapshot = try R.saving([expense, R.refund(2_000, of: expense, account: F.savingsID)])
        #expect(spending(snapshot, october) == 3_000)
    }

    @Test("Amounts 1–2: ₹19.99 nets to exactly 0; JPY 1,500 − 500 and BHD 1.250 − 0.250 net exactly")
    func exactCurrencies() throws {
        let inr = R.expense(Decimal(string: "19.99")!)
        let jpy = R.expense(1_500, account: F.jpyID)
        let bhd = R.expense(Decimal(string: "1.250")!, account: R.bhdID)
        let snapshot = try R.saving([
            inr, R.refund(Decimal(string: "19.99")!, of: inr),
            jpy, R.refund(500, of: jpy, account: F.jpyID),
            bhd, R.refund(Decimal(string: "0.250")!, of: bhd, account: R.bhdID),
        ])
        #expect(spending(snapshot, october) == 0)
        #expect(spending(snapshot, october, currency: "JPY") == 1_000)
        #expect(spending(snapshot, october, currency: "BHD") == Decimal(string: "1.000")!)
    }
}

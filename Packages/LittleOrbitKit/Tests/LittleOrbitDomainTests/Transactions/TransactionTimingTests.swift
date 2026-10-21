import Foundation
import LittleOrbitDomain
import Testing

@Suite("Current balance and Upcoming (D21)")
struct TransactionTimingTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    @Test("Today is the device's calendar day")
    func today() {
        let now = F.date(2026, 10, 20, 23, 59)
        #expect(TransactionTiming.today(now, timeZone: TimeZone(identifier: F.india)!) == F.day(2026, 10, 20))
        #expect(
            TransactionTiming.today(now, timeZone: TimeZone(identifier: "America/New_York")!) == F.day(2026, 10, 20)
        )
    }

    @Test("Dated today at 23:59 counts; next month is Upcoming (S11, S13)")
    func datedUpToToday() {
        let today = F.day(2026, 10, 20)
        let tonight = F.expense(100, on: F.date(2026, 10, 20, 23, 59))
        let nextMonth = F.expense(2_000, on: F.date(2026, 11, 20))
        #expect(!TransactionTiming.isUpcoming(tonight, today: today))
        #expect(TransactionTiming.isUpcoming(nextMonth, today: today))
        #expect(TransactionTiming.dated(upTo: today, [tonight, nextMonth]).map(\.id) == [tonight.id])
    }

    @Test("The account list's current balance leaves out Upcoming items until their date (S11, S12)")
    func listUsesCurrentBalance() throws {
        let upcoming = F.expense(2_000, on: F.date(2026, 11, 20))
        let listing = try ListAccounts()(
            accounts: F.accounts,
            transactions: [upcoming],
            showHidden: false,
            today: F.day(2026, 10, 20),
        )
        #expect(listing.assets.first { $0.account.id == F.savingsID }?.balance == 10_000)
        #expect(listing.assets.first { $0.account.id == F.savingsID }?.hasTransactions == true)
        let later = try ListAccounts()(
            accounts: F.accounts,
            transactions: [upcoming],
            showHidden: false,
            today: F.day(2026, 11, 20),
        )
        #expect(later.assets.first { $0.account.id == F.savingsID }?.balance == 8_000)
    }

    @Test("Net wealth uses the current balance too")
    func netWealthUsesCurrentBalance() throws {
        let upcoming = F.expense(2_000, on: F.date(2026, 11, 20))
        let totals = try ComputeNetWealth(defaultCurrency: "INR")(
            accounts: F.accounts,
            transactions: [upcoming],
            today: F.day(2026, 10, 20),
        )
        #expect(totals.first?.amount == 11_000)
    }
}

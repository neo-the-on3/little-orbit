import Foundation
import LittleOrbitDomain
import Testing

@Suite("Account history")
struct AccountHistoryTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    let today = TransactionFixture.day(2026, 10, 20)

    private var account: Account { F.accounts[0] }

    @Test("Grouped by day, newest first, with the balance after each row (AC, S1, S4)")
    func grouping() {
        let first = F.income(5_000, on: F.date(2026, 10, 19, 9))
        let second = F.expense(250, on: F.date(2026, 10, 20, 8))
        let third = F.expense(1_000, on: F.date(2026, 10, 20, 18))
        let history = BuildAccountHistory()(account: account, transactions: [second, first, third], today: today)
        #expect(history.days.map(\.day) == [F.day(2026, 10, 20), F.day(2026, 10, 19)])
        #expect(history.days[0].entries.map(\.transaction.id) == [third.id, second.id])
        #expect(history.days[0].entries.map(\.balanceAfter) == [13_750, 14_750])
        #expect(history.days[1].entries.map(\.balanceAfter) == [15_000])
        #expect(history.days[0].netChange == -1_250)
        #expect(history.currentBalance == 13_750)
        #expect(history.upcoming.isEmpty && history.balanceAfterUpcoming == nil)
    }

    @Test("Upcoming sits on top with projected balances, newest first (S11, S76)")
    func upcoming() {
        let rent = F.expense(18_000, on: F.date(2026, 11, 1))
        let power = F.expense(750, on: F.date(2026, 11, 3))
        let history = BuildAccountHistory()(account: account, transactions: [power, rent], today: today)
        #expect(history.currentBalance == 10_000)
        #expect(history.upcoming.map(\.transaction.id) == [power.id, rent.id])
        #expect(history.upcoming.map(\.balanceAfter) == [-8_750, -8_000])
        #expect(history.balanceAfterUpcoming == -8_750)
        #expect(history.upcomingTotal == -18_750)
    }

    @Test("Transfers count on both sides; cross-currency uses the received amount (S3, S10)")
    func transfers() {
        let out = F.transfer(1_000, on: F.date(2026, 10, 20), from: F.savingsID, to: F.usdID, received: 12)
        let mine = BuildAccountHistory()(account: account, transactions: [out], today: today)
        #expect(mine.currentBalance == 9_000)
        let usd = BuildAccountHistory()(account: F.accounts[2], transactions: [out], today: today)
        #expect(usd.currentBalance == 112)
        #expect(usd.days.first?.entries.first?.effect == 12)
    }

    @Test("Grouping keeps the entry time zone: 31 Dec 23:59 in Kolkata stays on 31 Dec (S29)")
    func timeZones() {
        let late = F.expense(10, on: F.date(2026, 12, 31, 23, 59))
        let history = BuildAccountHistory()(account: account, transactions: [late], today: F.day(2027, 1, 5))
        #expect(history.days.map(\.day) == [F.day(2026, 12, 31)])
    }

    @Test("A DST day lists a row once (S30)")
    func dst() {
        let london = F.expense(10, on: F.date(2026, 10, 25, 1, 30, zone: "Europe/London"), zone: "Europe/London")
        let history = BuildAccountHistory()(account: account, transactions: [london], today: F.day(2026, 10, 26))
        #expect(history.days.count == 1)
        #expect(history.days[0].day == F.day(2026, 10, 25))
    }

    @Test("10,000 transactions: the oldest row's balance builds back to the opening balance (S31)")
    func large() {
        var items: [Transaction] = []
        let start = F.date(2020, 1, 1)
        for index in 0..<10_000 {
            items.append(F.expense(1, on: start.addingTimeInterval(Double(index) * 3_600)))
        }
        let history = BuildAccountHistory()(account: account, transactions: items, today: today)
        #expect(history.currentBalance == 0)
        let oldest = history.days.last!.entries.last!
        #expect(oldest.balanceAfter - oldest.effect == account.openingBalance)
    }

    @Test("Other accounts' rows are left out")
    func filtersAccount() {
        let other = F.expense(10, on: F.date(2026, 10, 20), account: F.walletID)
        let history = BuildAccountHistory()(account: account, transactions: [other], today: today)
        #expect(history.days.isEmpty)
    }
}

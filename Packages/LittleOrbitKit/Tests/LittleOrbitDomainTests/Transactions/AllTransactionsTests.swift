import Foundation
import LittleOrbitDomain
import Testing

@Suite("All Transactions list (#243, D421)")
struct AllTransactionsTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private let build = BuildAllTransactions()
    private let today = TransactionFixture.day(2026, 10, 28)

    @Test("Every live account's transactions, newest first by day, hidden accounts included (D421.10)")
    func newestFirstAcrossAccounts() {
        var accounts = F.accounts
        accounts[1].isHidden = true
        let bakery = F.expense(8, on: F.date(2026, 10, 27), account: F.usdID)
        let metro = F.expense(12, on: F.date(2026, 10, 28), account: F.savingsID)
        let tea = F.expense(60, on: F.date(2026, 10, 26), account: F.walletID)
        let list = build(accounts: accounts, transactions: [tea, bakery, metro], today: today)

        #expect(list.upcoming.isEmpty)
        #expect(list.days.map(\.day) == [F.day(2026, 10, 28), F.day(2026, 10, 27), F.day(2026, 10, 26)])
        #expect(list.entries.map(\.id) == [metro.id, bakery.id, tea.id])
        #expect(list.entries.map(\.account.id) == [F.savingsID, F.usdID, F.walletID])
        #expect(list.entries.map(\.effect) == [-12, -8, -60])
    }

    @Test("A transfer is listed once, under its source account, with its effect there (D25)")
    func transferOnce() {
        let move = F.transfer(100, on: F.date(2026, 10, 25), from: F.usdID, to: F.savingsID)
        let list = build(accounts: F.accounts, transactions: [move], today: today)
        #expect(list.entries.count == 1)
        #expect(list.entries.first?.account.id == F.usdID)
        #expect(list.entries.first?.effect == -100)
    }

    @Test("Ties keep the register's order reversed: time, then creation, then id")
    func tiesAreStable() {
        let noon = F.date(2026, 10, 27, 12)
        let first = F.expense(1, on: noon, created: F.date(2026, 10, 27, 9))
        let second = F.expense(2, on: noon, created: F.date(2026, 10, 27, 10))
        let later = F.expense(3, on: F.date(2026, 10, 27, 18))
        let list = build(accounts: F.accounts, transactions: [first, later, second], today: today)
        #expect(list.entries.map(\.id) == [later.id, second.id, first.id])
        #expect(list.days.count == 1)
    }

    @Test("Hand-entered future rows are Upcoming, newest first; deleted rows and accounts aren't listed (D426.4)")
    func upcomingAndDeleted() {
        var accounts = F.accounts
        accounts[3].deletedAt = F.date(2026, 10, 1)
        let concert = F.expense(60, on: F.date(2026, 12, 2), account: F.usdID)
        let soon = F.expense(5, on: F.date(2026, 11, 3), account: F.usdID)
        var gone = F.expense(9, on: F.date(2026, 10, 20))
        gone.deletedAt = F.date(2026, 10, 21)
        let orphan = F.expense(7, on: F.date(2026, 10, 20), account: F.jpyID)
        let list = build(accounts: accounts, transactions: [soon, concert, gone, orphan], today: today)
        #expect(list.upcoming.map(\.id) == [concert.id, soon.id])
        #expect(list.days.isEmpty)
        #expect(!list.isEmpty)
        #expect(build(accounts: accounts, transactions: [], today: today).isEmpty)
    }

    @Test("A transfer whose source account is gone stays listed under its destination")
    func orphanedTransfer() {
        let move = F.transfer(50, on: F.date(2026, 10, 20), from: F.jpyID, to: F.savingsID)
        let accounts = F.accounts.filter { $0.id != F.jpyID }
        let list = build(accounts: accounts, transactions: [move], today: today)
        #expect(list.entries.first?.account.id == F.savingsID)
        #expect(list.entries.first?.effect == 50)
    }
}

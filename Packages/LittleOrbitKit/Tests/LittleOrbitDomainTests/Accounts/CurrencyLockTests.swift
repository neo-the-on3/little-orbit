import Foundation
import LittleOrbitDomain
import Testing

/// D54 and D104: the currency locks once anything refers to the account.
@Suite("Currency lock")
struct CurrencyLockTests {
    @Test("No transactions and no scheduled items leaves the currency editable")
    func unlocked() {
        #expect(!CurrencyLock.isLocked(accountID: UUID(), transactions: []))
    }

    @Test("Any own transaction locks it")
    func ownTransaction() {
        let pocket = AccountFixture.euroPocket
        #expect(CurrencyLock.isLocked(accountID: pocket.id, transactions: [AccountFixture.expense(1, from: pocket)]))
    }

    @Test("Being only a transfer's destination locks it (S82)")
    func transferDestination() {
        let pocket = AccountFixture.euroPocket
        let transfer = AccountFixture.transfer(10, from: AccountFixture.holidayFund, to: pocket, received: 9)
        #expect(CurrencyLock.isLocked(accountID: pocket.id, transactions: [transfer]))
    }

    @Test("A scheduled item that points at the account locks it (S83)")
    func scheduledItem() {
        let pocket = AccountFixture.euroPocket
        #expect(CurrencyLock.isLocked(accountID: pocket.id, transactions: [], scheduledAccountIDs: [pocket.id]))
    }

    @Test("The message matches D104 exactly")
    func message() {
        #expect(
            CurrencyLock.message == "Currency can’t be changed once the account has transactions or scheduled items."
        )
    }
}

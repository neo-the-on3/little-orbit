import Foundation
import LittleOrbitDomain
import Testing

/// What an undoable change records about itself. Its Undo and Redo names are in `LittleOrbitFeatures`.
@Suite("Transaction changes")
struct TransactionChangeTests {
    @Test("Deleting an account is about that account (#93)")
    func deleteAccount() {
        let household = Account(name: "Household Card", type: .creditCard, currencyCode: "EUR")
        let change = TransactionChange.removedAccount(RemovedAccount(account: household, transactions: []))
        #expect(change.accountIDs == [household.id])
        #expect(change.transactionIDs.isEmpty)
    }

    @Test("A change lists the transactions it touches")
    func transactionIDs() {
        let one = Transaction(type: .expense, amount: 1)
        #expect(TransactionChange.removed([RemovedTransaction(transaction: one)]).transactionIDs == [one.id])
        #expect(TransactionChange.added([one.id]).transactionIDs == [one.id])
        #expect(TransactionChange.replaced([one]).transactionIDs == [one.id])
    }
}

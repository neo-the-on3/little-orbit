import Foundation
import LittleOrbitDomain
import Testing

/// D19 and PM answer 1 on #22: the delete confirmation counts what goes with the account.
@Suite("Account deletion impact")
struct AccountDeletionTests {
    private let assess = AssessAccountDeletion()

    @Test("Counts own transactions and transfers in either direction")
    func countsTransactionsAndTransfers() {
        let savings = AccountFixture.everydaySavings
        let rainyDay = Account(name: "Rainy Day Savings", type: .savings, currencyCode: "INR")
        var transactions = (0..<117).map { _ in AccountFixture.expense(10, from: savings) }
        transactions.append(AccountFixture.transfer(100, from: savings, to: rainyDay))
        transactions.append(AccountFixture.transfer(100, from: savings, to: rainyDay))
        transactions.append(AccountFixture.transfer(100, from: rainyDay, to: savings))
        transactions.append(AccountFixture.expense(5, from: rainyDay))
        let impact = assess(accountID: savings.id, transactions: transactions)
        #expect(impact == AccountDeletionImpact(transactionCount: 120, transferCount: 3))
    }

    @Test("An account that only receives transfers counts them (S14)")
    func destinationOnly() {
        let source = AccountFixture.everydaySavings
        let destination = AccountFixture.cornerWallet
        let transactions = [
            AccountFixture.transfer(100, from: source, to: destination),
            AccountFixture.transfer(200, from: source, to: destination),
        ]
        let impact = assess(accountID: destination.id, transactions: transactions)
        #expect(impact == AccountDeletionImpact(transactionCount: 2, transferCount: 2))
    }

    @Test("No transactions still reports 0 (S16)")
    func none() {
        let impact = assess(accountID: UUID(), transactions: [])
        #expect(impact == AccountDeletionImpact(transactionCount: 0, transferCount: 0))
    }

    @Test("Deleted transactions are not counted")
    func ignoresDeleted() {
        let savings = AccountFixture.everydaySavings
        var gone = AccountFixture.expense(10, from: savings)
        gone.deletedAt = Date()
        #expect(assess(accountID: savings.id, transactions: [gone]).transactionCount == 0)
    }
}

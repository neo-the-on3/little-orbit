import Foundation
import LittleOrbitDomain
import Testing

/// What the Payees screen reads (#24): each live payee, what uses it, and the last-used category the survivor of
/// a merge keeps (D291.5). Names are made up.
@Suite("Payee listing (#24)")
@MainActor
struct PayeeListingTests {
    private let account = Account(name: "Wallet", type: .cash, currencyCode: "INR")
    private let food = TransactionCategory(name: "Food", kind: .expense, sortOrder: 0)
    private let shopping = TransactionCategory(name: "Shopping", kind: .expense, sortOrder: 1)
    private let travel = TransactionCategory(name: "Travel", kind: .expense, sortOrder: 2)

    private func expense(payeeID: UUID?) -> Transaction {
        Transaction(type: .expense, amount: 10, accountID: account.id, categoryID: food.id, payeeID: payeeID)
    }

    private func repository(_ payees: [Payee], _ transactions: [Transaction] = []) throws -> FakeLedgerRepository {
        let repository = try FakeLedgerRepository(
            accounts: [account],
            categories: [food, shopping, travel],
            transactions: [],
        )
        for payee in payees {
            try repository.savePayee(payee)
        }
        for transaction in transactions {
            try repository.saveTransaction(transaction)
        }
        return repository
    }

    @Test("The listing counts each payee’s live transactions and finds its last-used category")
    func listing() throws {
        let parcel = Payee(name: "Parcel Point", defaultCategoryID: shopping.id)
        let bakery = Payee(name: "Corner Bakery")
        let repository = try repository(
            [parcel, bakery],
            [expense(payeeID: parcel.id), expense(payeeID: parcel.id), expense(payeeID: nil)],
        )
        let listing = try DefaultLoadPayeesUseCase(repository: repository).listing()
        #expect(Set(listing.payees.map(\.id)) == [parcel.id, bakery.id])
        #expect(listing.uses(of: parcel.id) == 2)
        #expect(listing.uses(of: bakery.id) == 0)
        #expect(listing.lastUsedCategory(of: parcel)?.id == shopping.id)
        #expect(listing.lastUsedCategory(of: bakery) == nil)
    }

    @Test("The kept category is the one the merge itself keeps: the most recently used payee’s (D291.5)")
    func keptCategoryMatchesMerge() throws {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let parcel = Payee(name: "Parcel Point", defaultCategoryID: shopping.id, lastUsedAt: day)
        let parcelIn = Payee(name: "PARCELPOINT.IN", defaultCategoryID: travel.id, lastUsedAt: day + 86_400)
        let unused = Payee(name: "PARCEL PT")
        let repository = try repository([parcel, parcelIn, unused])
        let ids = [parcel.id, parcelIn.id, unused.id]
        let listing = try DefaultLoadPayeesUseCase(repository: repository).listing()
        #expect(listing.keptCategory(merging: ids, into: parcel.id)?.id == travel.id)
        #expect(listing.keptCategory(merging: [unused.id], into: unused.id) == nil)

        try CategoryUseCases(repository: repository).managePayees.merge(ids, into: parcel.id)
        let survivor = try #require(try repository.payees().first { $0.id == parcel.id })
        #expect(survivor.defaultCategoryID == travel.id)
    }
}

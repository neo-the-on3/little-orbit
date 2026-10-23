import Foundation
import LittleOrbitDomain

/// Made-up data for the #55 refund tests, on top of `TransactionFixture`'s accounts: 'Everyday Savings' and
/// 'Corner Wallet' (INR), 'USD Wallet' and 'Yen Pocket' (JPY). Dates are in Asia/Calcutta unless a test says
/// otherwise.
enum RefundFixture {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    static let cardID = UUID(uuidString: "A0000000-0000-4000-8000-000000000055")!
    static let bhdID = UUID(uuidString: "A0000000-0000-4000-8000-000000000056")!
    static let groceriesID = UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!
    static let diningID = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
    static let shoppingID = UUID(uuidString: "C0000000-0000-4000-8000-000000000003")!
    static let salaryID = UUID(uuidString: "C0000000-0000-4000-8000-000000000004")!

    static var accounts: [Account] {
        F.accounts + [
            Account(id: cardID, name: "Rewards Card", type: .creditCard, currencyCode: "INR", openingBalance: 0),
            Account(id: bhdID, name: "Pearl Account", type: .checking, currencyCode: "BHD", openingBalance: 0),
        ]
    }

    static var categories: [TransactionCategory] {
        [
            TransactionCategory(id: groceriesID, name: "Groceries", kind: .expense),
            TransactionCategory(id: diningID, name: "Dining", kind: .expense),
            TransactionCategory(id: shoppingID, name: "Shopping", kind: .expense),
            TransactionCategory(id: salaryID, name: "Salary", kind: .income),
        ]
    }

    /// The accounts and categories, with no transactions.
    static var ledger: LedgerSnapshot {
        LedgerSnapshot(accounts: accounts, categories: categories)
    }

    static let october = F.date(2026, 10, 10)

    static func expense(
        _ amount: Decimal,
        in category: UUID? = groceriesID,
        on date: Date = october,
        account: UUID = F.savingsID,
        zone: String = F.india,
    ) -> Transaction {
        Transaction(
            type: .expense,
            amount: amount,
            date: date,
            timeZoneID: zone,
            accountID: account,
            categoryID: category,
            createdAt: date,
        )
    }

    /// A refund of `original`, in its category unless one is given.
    static func refund(
        _ amount: Decimal,
        of original: Transaction?,
        in category: UUID?? = .none,
        on date: Date = october,
        account: UUID = F.savingsID,
        zone: String = F.india,
        isRefund: Bool = true,
    ) -> Transaction {
        Transaction(
            type: .income,
            amount: amount,
            date: date,
            timeZoneID: zone,
            accountID: account,
            categoryID: category.map { $0 } ?? original?.categoryID ?? groceriesID,
            refundOfID: original?.id,
            isRefund: isRefund,
            createdAt: date,
        )
    }

    /// Saves each transaction in order through `LedgerBook`, as the stores do.
    static func saving(_ transactions: [Transaction], in snapshot: LedgerSnapshot = ledger) throws -> LedgerSnapshot {
        var snapshot = snapshot
        for transaction in transactions {
            snapshot = try LedgerBook.savingTransaction(transaction, in: snapshot, now: transaction.createdAt)
        }
        return snapshot
    }

    @MainActor
    static func repository(_ transactions: [Transaction] = []) throws -> FakeLedgerRepository {
        try FakeLedgerRepository(accounts: accounts, categories: categories, transactions: transactions)
    }
}

extension LedgerSnapshot {
    func transaction(_ id: UUID) -> Transaction? {
        transactions.first { $0.id == id }
    }
}

extension FakeLedgerRepository {
    func stored(_ id: UUID) throws -> Transaction? {
        try transactions().first { $0.id == id }
    }
}

import Foundation
import LittleOrbitDomain

/// Fixture "F34" from #34's QA scenarios, built through `LedgerBook` so every record passes the ledger rules.
/// All names and amounts are made up. Dates are in Asia/Calcutta.
struct SplitsRefundsFixture {
    let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR", openingBalance: 100_000)
    let wallet = Account(name: "Pocket Wallet", type: .cash, currencyCode: "INR")
    let travel = Account(name: "Travel Card", type: .creditCard, currencyCode: "USD")

    let groceries = TransactionCategory(name: "Groceries", kind: .expense)
    let household = TransactionCategory(name: "Household", kind: .expense)
    let drinks = TransactionCategory(name: "Drinks", kind: .expense)
    let shopping = TransactionCategory(name: "Shopping", kind: .expense)
    let pharmacy = TransactionCategory(name: "Pharmacy", kind: .expense)
    let salary = TransactionCategory(name: "Salary", kind: .income)

    private(set) var snapshot = LedgerSnapshot()
    private let now = TransactionFixture.date(2026, 10, 23)

    static func date(_ month: Int, _ day: Int) -> Date {
        TransactionFixture.date(2026, month, day)
    }

    init() throws {
        snapshot = LedgerSnapshot(
            accounts: [savings, wallet, travel],
            categories: [groceries, household, drinks, shopping, pharmacy, salary],
        )
    }

    /// Adds a payee record as it is.
    @discardableResult
    mutating func addPayee(named name: String) -> Payee {
        let payee = Payee(name: name, createdAt: now, updatedAt: now)
        snapshot.payees.append(payee)
        return payee
    }

    /// Marks a payee record deleted, the way a payee cleanup leaves it.
    mutating func deletePayee(_ payee: Payee) {
        if let index = snapshot.payees.firstIndex(where: { $0.id == payee.id }) {
            snapshot.payees[index].deletedAt = now
        }
    }

    /// Adds categories as they are, for trees the default list doesn't have.
    mutating func addCategories(_ categories: [TransactionCategory]) {
        snapshot.categories += categories
    }

    /// Puts `category` in place of the stored one with its ID: a move, an archive or a delete.
    mutating func replaceCategory(_ category: TransactionCategory) {
        if let index = snapshot.categories.firstIndex(where: { $0.id == category.id }) {
            snapshot.categories[index] = category
        }
    }

    @discardableResult
    mutating func expense(
        _ amount: Decimal,
        in category: TransactionCategory? = nil,
        on date: Date,
        account: Account? = nil,
        payee: Payee? = nil,
    ) throws -> Transaction {
        let transaction = Transaction(
            type: .expense,
            amount: amount,
            date: date,
            timeZoneID: TransactionFixture.india,
            accountID: (account ?? savings).id,
            categoryID: category?.id,
            payeeID: payee?.id,
        )
        snapshot = try LedgerBook.savingTransaction(transaction, in: snapshot, now: now)
        return transaction
    }

    @discardableResult
    mutating func split(_ lines: [(TransactionCategory, Decimal)], on date: Date) throws -> Transaction {
        let total = lines.reduce(Decimal(0)) { $0 + $1.1 }
        let transaction = try expense(total, on: date)
        let splits = lines.enumerated()
            .map { index, line in
                TransactionSplit(categoryID: line.0.id, amount: line.1, sortOrder: Double(index))
            }
        snapshot = try LedgerBook.replacingSplits(splits, for: transaction.id, in: snapshot, now: now)
        return transaction
    }

    /// A refund linked to `expense`, or an orphaned one ('Refund (original deleted)') when `expense` is nil.
    @discardableResult
    mutating func refund(
        _ amount: Decimal,
        of expense: Transaction?,
        in category: TransactionCategory,
        on date: Date,
        account: Account? = nil,
    ) throws -> Transaction {
        let refund = Transaction(
            type: .income,
            amount: amount,
            date: date,
            timeZoneID: TransactionFixture.india,
            accountID: (account ?? savings).id,
            categoryID: category.id,
            refundOfID: expense?.id,
            isRefund: true,
        )
        if expense == nil {
            // The state deleting the expense leaves (D19, #55). The ledger doesn't make orphans yet, so the
            // fixture writes this one directly.
            snapshot.transactions.append(refund)
        } else {
            snapshot = try LedgerBook.savingTransaction(refund, in: snapshot, now: now)
        }
        return refund
    }

    mutating func income(_ amount: Decimal, in category: TransactionCategory, on date: Date) throws {
        let income = Transaction(
            type: .income,
            amount: amount,
            date: date,
            timeZoneID: TransactionFixture.india,
            accountID: savings.id,
            categoryID: category.id,
        )
        snapshot = try LedgerBook.savingTransaction(income, in: snapshot, now: now)
    }

    mutating func transfer(_ amount: Decimal, on date: Date) throws {
        let transfer = Transaction(
            type: .transfer,
            amount: amount,
            date: date,
            timeZoneID: TransactionFixture.india,
            accountID: savings.id,
            transferAccountID: wallet.id,
        )
        snapshot = try LedgerBook.savingTransaction(transfer, in: snapshot, now: now)
    }
}

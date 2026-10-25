import Foundation
import LittleOrbitDomain

/// Made-up data for the #25 budget tests, on top of `TransactionFixture`'s accounts ('Everyday Savings' and
/// 'Corner Wallet' in INR, 'USD Wallet', 'Yen Pocket' in JPY). Food has the subcategories Groceries and
/// Restaurants. Dates are in Asia/Calcutta.
enum BudgetFixture {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    static let foodID = UUID(uuidString: "B5000000-0000-4000-8000-000000000001")!
    static let groceriesID = UUID(uuidString: "B5000000-0000-4000-8000-000000000002")!
    static let restaurantsID = UUID(uuidString: "B5000000-0000-4000-8000-000000000003")!
    static let shoppingID = UUID(uuidString: "B5000000-0000-4000-8000-000000000004")!
    static let householdID = UUID(uuidString: "B5000000-0000-4000-8000-000000000005")!
    static let salaryID = UUID(uuidString: "B5000000-0000-4000-8000-000000000006")!
    /// An income category with the same name as the expense one (S66).
    static let shoppingIncomeID = UUID(uuidString: "B5000000-0000-4000-8000-000000000007")!
    static let travelID = UUID(uuidString: "B5000000-0000-4000-8000-000000000008")!

    static var categories: [TransactionCategory] {
        [
            TransactionCategory(id: foodID, name: "Food", kind: .expense, sortOrder: 0),
            TransactionCategory(id: groceriesID, name: "Groceries", kind: .expense, parentID: foodID, sortOrder: 0),
            TransactionCategory(
                id: restaurantsID,
                name: "Restaurants",
                kind: .expense,
                parentID: foodID,
                sortOrder: 1,
            ),
            TransactionCategory(id: shoppingID, name: "Shopping", kind: .expense, sortOrder: 1),
            TransactionCategory(id: householdID, name: "Household", kind: .expense, sortOrder: 2),
            TransactionCategory(id: travelID, name: "Travel", kind: .expense, sortOrder: 3),
            TransactionCategory(id: salaryID, name: "Salary", kind: .income, sortOrder: 0),
            TransactionCategory(id: shoppingIncomeID, name: "Shopping", kind: .income, sortOrder: 1),
        ]
    }

    static var ledger: LedgerSnapshot {
        LedgerSnapshot(accounts: F.accounts, categories: categories)
    }

    static func budget(
        _ name: String = "Eating out",
        limit: Decimal = 8_000,
        categories: [UUID] = [restaurantsID],
        from start: CalendarDay = F.day(2026, 11, 1),
        recurrence: BudgetRecurrence = .monthly,
        currency: String = "INR",
        unspent: Bool = false,
        overspending: Bool = false,
    ) -> Budget {
        Budget(
            name: name,
            currencyCode: currency,
            categoryIDs: categories,
            startDay: start,
            recurrence: recurrence,
            limit: limit,
            carriesOverUnspent: unspent,
            carriesOverOverspending: overspending,
            createdAt: F.date(2026, 10, 1),
        )
    }

    static func expense(
        _ amount: Decimal,
        in category: UUID? = restaurantsID,
        on date: Date,
        account: UUID = F.savingsID,
    ) -> Transaction {
        Transaction(
            type: .expense,
            amount: amount,
            date: date,
            timeZoneID: F.india,
            accountID: account,
            categoryID: category,
            createdAt: date,
        )
    }

    /// Saves the transactions and budgets in order through `LedgerBook`, as the stores do.
    static func saving(
        _ transactions: [Transaction],
        budgets: [Budget] = [],
        in snapshot: LedgerSnapshot = ledger,
    ) throws -> LedgerSnapshot {
        var snapshot = snapshot
        for transaction in transactions {
            snapshot = try LedgerBook.savingTransaction(transaction, in: snapshot, now: transaction.createdAt)
        }
        for budget in budgets {
            snapshot = try LedgerBook.savingBudget(budget, in: snapshot, now: budget.createdAt)
        }
        return snapshot
    }
}

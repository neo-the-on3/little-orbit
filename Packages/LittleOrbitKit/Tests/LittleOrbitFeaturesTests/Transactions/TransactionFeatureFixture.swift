import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence

/// Made-up ledger from the #23 designs: today is Tue 20 Oct 2026, 10:00 in Asia/Calcutta.
@MainActor
enum TransactionFeatureFixture {
    static let india = Locale(identifier: "en_IN")
    static let zoneID = "Asia/Kolkata"
    static let zone = TimeZone(identifier: zoneID)!
    static let savingsID = UUID(uuidString: "5A000000-0000-4000-8000-000000000001")!
    static let walletID = UUID(uuidString: "5A000000-0000-4000-8000-000000000002")!
    static let usdID = UUID(uuidString: "5A000000-0000-4000-8000-000000000003")!
    static let cardID = UUID(uuidString: "5A000000-0000-4000-8000-000000000004")!

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static let now = date(2026, 10, 20, 10)
    static let today = TransactionTiming.today(now, timeZone: zone)

    static func accounts() -> [Account] {
        [
            Account(
                id: savingsID,
                name: "Everyday Savings",
                type: .savings,
                currencyCode: "INR",
                openingBalance: 10_000,
                sortOrder: 1,
            ),
            Account(
                id: walletID,
                name: "Corner Wallet",
                type: .cash,
                currencyCode: "INR",
                openingBalance: 1_000,
                sortOrder: 2,
            ),
            Account(
                id: usdID,
                name: "USD Wallet",
                type: .cash,
                currencyCode: "USD",
                openingBalance: 100,
                sortOrder: 3,
            ),
            Account(
                id: cardID,
                name: "Rewards Card",
                type: .creditCard,
                currencyCode: "INR",
                openingBalance: 0,
                sortOrder: 4,
                creditLimit: 50_000,
            ),
        ]
    }

    static func repository(_ transactions: [Transaction] = []) throws -> InMemoryLedgerRepository {
        let repository = InMemoryLedgerRepository(now: { now })
        for account in accounts() {
            try repository.saveAccount(account)
        }
        try repository.seedDefaultCategories()
        for transaction in transactions {
            try repository.saveTransaction(transaction)
        }
        return repository
    }

    static func expense(
        _ amount: Decimal,
        on date: Date,
        account: UUID = savingsID,
        category: UUID? = nil,
        payee: UUID? = nil,
        details: String? = nil,
    ) -> Transaction {
        Transaction(
            type: .expense,
            amount: amount,
            date: date,
            timeZoneID: zoneID,
            accountID: account,
            categoryID: category,
            payeeID: payee,
            details: details,
            createdAt: date,
        )
    }

    static func income(_ amount: Decimal, on date: Date, account: UUID = savingsID, category: UUID? = nil)
        -> Transaction
    {
        Transaction(
            type: .income,
            amount: amount,
            date: date,
            timeZoneID: zoneID,
            accountID: account,
            categoryID: category,
            createdAt: date,
        )
    }

    static func transfer(
        _ amount: Decimal,
        on date: Date,
        from source: UUID = savingsID,
        to destination: UUID = cardID,
        received: Decimal? = nil,
        details: String? = nil,
    ) -> Transaction {
        Transaction(
            type: .transfer,
            amount: amount,
            date: date,
            timeZoneID: zoneID,
            accountID: source,
            details: details,
            transferAccountID: destination,
            destinationAmount: received,
            createdAt: date,
        )
    }
}

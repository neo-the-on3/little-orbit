import Foundation
import LittleOrbitDomain

/// Made-up data for the #23 tests. Dates are in Asia/Calcutta unless a test says otherwise.
enum TransactionFixture {
    static let india = "Asia/Calcutta"
    static let savingsID = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
    static let walletID = UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!
    static let usdID = UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!
    static let jpyID = UUID(uuidString: "A0000000-0000-4000-8000-000000000004")!

    static var accounts: [Account] {
        [
            Account(
                id: savingsID,
                name: "Everyday Savings",
                type: .savings,
                currencyCode: "INR",
                openingBalance: 10_000,
            ),
            Account(id: walletID, name: "Corner Wallet", type: .cash, currencyCode: "INR", openingBalance: 1_000),
            Account(id: usdID, name: "USD Wallet", type: .checking, currencyCode: "USD", openingBalance: 100),
            Account(id: jpyID, name: "Yen Pocket", type: .cash, currencyCode: "JPY", openingBalance: 0),
        ]
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, zone: String = india)
        -> Date
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    static func expense(
        _ amount: Decimal,
        on date: Date,
        account: UUID = savingsID,
        zone: String = india,
        created: Date? = nil,
    ) -> Transaction {
        Transaction(
            type: .expense,
            amount: amount,
            date: date,
            timeZoneID: zone,
            accountID: account,
            createdAt: created ?? date,
        )
    }

    static func income(_ amount: Decimal, on date: Date, account: UUID = savingsID) -> Transaction {
        Transaction(type: .income, amount: amount, date: date, timeZoneID: india, accountID: account, createdAt: date)
    }

    static func transfer(
        _ amount: Decimal,
        on date: Date,
        from: UUID = savingsID,
        to destination: UUID = walletID,
        received: Decimal? = nil,
    ) -> Transaction {
        Transaction(
            type: .transfer,
            amount: amount,
            date: date,
            timeZoneID: india,
            accountID: from,
            transferAccountID: destination,
            destinationAmount: received,
            createdAt: date,
        )
    }

    /// A tag, made here because test files also import Testing, whose `Tag` would be ambiguous.
    static func tag(_ name: String) -> Tag {
        Tag(name: name)
    }
}

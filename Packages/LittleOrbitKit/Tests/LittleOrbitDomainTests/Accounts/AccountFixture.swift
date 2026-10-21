import Foundation
import LittleOrbitDomain

/// Made-up fixture from Tester's QA v2.1 on #22. Default currency INR.
enum AccountFixture {
    static let everydaySavings = Account(
        name: "Everyday Savings",
        type: .savings,
        currencyCode: "INR",
        openingBalance: 25_000,
        sortOrder: 1,
    )
    static let cornerWallet = Account(
        name: "Corner Wallet",
        type: .cash,
        currencyCode: "INR",
        openingBalance: Decimal(string: "1650.50")!,
        sortOrder: 2,
    )
    static let travelCard = Account(
        name: "Travel Card",
        type: .creditCard,
        currencyCode: "INR",
        openingBalance: -30_000,
        sortOrder: 3,
        creditLimit: 100_000,
        showAvailableCredit: true,
    )
    static let longTermFund = Account(
        name: "Long Term Fund",
        type: .investment,
        currencyCode: "INR",
        openingBalance: 20_000,
        isHidden: true,
        sortOrder: 4,
    )
    static let oldLocker = Account(
        name: "Old Locker",
        type: .other,
        currencyCode: "INR",
        openingBalance: 5_000,
        isHidden: true,
        includeInNetWorth: false,
        sortOrder: 5,
    )
    static let holidayFund = Account(
        name: "Holiday Fund",
        type: .savings,
        currencyCode: "USD",
        openingBalance: 1_240,
        sortOrder: 6,
    )
    static let euroPocket = Account(
        name: "Euro Pocket",
        type: .cash,
        currencyCode: "EUR",
        openingBalance: 300,
        sortOrder: 7,
    )

    static let all = [
        everydaySavings, cornerWallet, travelCard, longTermFund, oldLocker, holidayFund, euroPocket,
    ]

    static func expense(_ amount: Decimal, from account: Account) -> Transaction {
        Transaction(type: .expense, amount: amount, accountID: account.id)
    }

    static func transfer(
        _ amount: Decimal,
        from source: Account,
        to destination: Account,
        received: Decimal? = nil,
    ) -> Transaction {
        Transaction(
            type: .transfer,
            amount: amount,
            accountID: source.id,
            transferAccountID: destination.id,
            destinationAmount: received,
        )
    }
}

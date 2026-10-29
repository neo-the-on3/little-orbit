import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// #341: a row looks up its accounts, category and payee by id, from dictionaries built once per page, rather
/// than scanning the ledger's arrays for every row. Made-up data.
@Suite("Row lookups by id (#341)")
struct TransactionRowLookupsTests {
    static let checking = Account(name: "Everyday Checking", type: .checking, currencyCode: "USD", openingBalance: 0)
    static let savings = Account(name: "Holiday Savings", type: .savings, currencyCode: "EUR", openingBalance: 0)
    static let food = TransactionCategory(name: "Food & Dining", kind: .expense, iconName: "fork.knife")
    static let bakery = Payee(name: "Corner Bakery")

    @Test("Each record is found by its id; an unknown id finds nothing")
    func byID() {
        let lookups = TransactionRowLookups(
            accounts: [Self.checking, Self.savings],
            categories: [Self.food],
            payees: [Self.bakery],
        )
        #expect(lookups.accounts[Self.savings.id]?.name == "Holiday Savings")
        #expect(lookups.categories[Self.food.id]?.name == "Food & Dining")
        #expect(lookups.payees[Self.bakery.id]?.name == "Corner Bakery")
        #expect(lookups.payees[UUID()] == nil)
    }

    @Test("Two records with one id keep the first, as the array scan did")
    func duplicateKeepsFirst() {
        var renamed = Self.bakery
        renamed.name = "Bakery (old)"
        let lookups = TransactionRowLookups(accounts: [], categories: [], payees: [Self.bakery, renamed])
        #expect(lookups.payees[Self.bakery.id]?.name == "Corner Bakery")
    }

    @Test("A row built from shared lookups reads the same as one built from the ledger's arrays")
    func sameRow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!
        let buy = Transaction(
            type: .expense,
            amount: 8,
            date: day,
            timeZoneID: "UTC",
            accountID: Self.checking.id,
            categoryID: Self.food.id,
            payeeID: Self.bakery.id,
        )
        let move = Transaction(
            type: .transfer,
            amount: 100,
            date: day,
            timeZoneID: "UTC",
            accountID: Self.checking.id,
            transferAccountID: Self.savings.id,
            destinationAmount: 90,
        )
        let formatter = MoneyFormatter(locale: Locale(identifier: "en_US"))
        let text = TransactionText(locale: Locale(identifier: "en_US"))
        let today = CalendarDay(year: 2026, month: 10, day: 28)
        let fromArrays = TransactionRowContext(
            account: Self.checking,
            accounts: [Self.checking, Self.savings],
            categories: [Self.food],
            payees: [Self.bakery],
            formatter: formatter,
            text: text,
            today: today,
        )
        let fromLookups = TransactionRowContext(
            account: Self.checking,
            lookups: TransactionRowLookups(
                accounts: [Self.checking, Self.savings],
                categories: [Self.food],
                payees: [Self.bakery],
            ),
            formatter: formatter,
            text: text,
            today: today,
        )
        for transaction in [buy, move] {
            let entry = HistoryEntry(transaction: transaction, effect: -transaction.amount, balanceAfter: 0)
            let row = fromLookups.row(entry, isUpcoming: false)
            #expect(row == fromArrays.row(entry, isUpcoming: false))
        }
        let moveRow = fromLookups.row(
            HistoryEntry(transaction: move, effect: -100, balanceAfter: 0),
            isUpcoming: false,
        )
        #expect(moveRow.title == "To Holiday Savings")
        #expect(moveRow.subtitle.contains("90"))
        let buyRow = fromLookups.row(HistoryEntry(transaction: buy, effect: -8, balanceAfter: 0), isUpcoming: false)
        #expect(buyRow.title == "Corner Bakery")
        #expect(buyRow.categoryText == "Food & Dining")
    }
}

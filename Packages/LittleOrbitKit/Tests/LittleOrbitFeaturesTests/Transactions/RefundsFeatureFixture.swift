import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence

/// #34's own sample data for the feature tests, kept apart from #23's: here Travel Card is in USD. Names, dates
/// and amounts are made up.
@MainActor
struct RefundsFeatureFixture {
    static let kolkata = "Asia/Kolkata"
    static let london = "Europe/London"
    static let newYork = "America/New_York"
    static let now = date(2026, 10, 23, 10, 0, zone: kolkata)

    let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR", sortOrder: 1)
    let groceryCash = Account(name: "Grocery Cash", type: .cash, currencyCode: "INR", sortOrder: 2)
    let holidayFund = Account(name: "Holiday Fund", type: .savings, currencyCode: "INR", sortOrder: 3)
    let householdCard = Account(name: "Household Card", type: .creditCard, currencyCode: "INR", sortOrder: 4)
    let travelCard = Account(name: "Travel Card", type: .creditCard, currencyCode: "USD", sortOrder: 5)
    let shopping = TransactionCategory(name: "Shopping", kind: .expense)
    let repository: InMemoryLedgerRepository

    init() throws {
        repository = InMemoryLedgerRepository(now: { Self.now })
        for account in [savings, groceryCash, holidayFund, householdCard, travelCard] {
            try repository.saveAccount(account)
        }
        try repository.saveCategory(shopping)
    }

    var useCases: TransactionUseCases { TransactionUseCases(repository: repository) }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, zone: String)
        -> Date
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @discardableResult
    func expense(
        _ amount: Decimal,
        on date: Date,
        zone: String = kolkata,
        in account: Account? = nil,
        payee: Payee? = nil,
        details: String? = nil,
    ) throws -> Transaction {
        let expense = Transaction(
            type: .expense,
            amount: amount,
            date: date,
            timeZoneID: zone,
            accountID: (account ?? savings).id,
            categoryID: shopping.id,
            payeeID: payee?.id,
            details: details,
            createdAt: Self.now,
        )
        try repository.saveTransaction(expense)
        return expense
    }

    /// A refund linked to `expense`, or one whose expense was deleted ("Refund (original deleted)") when it's nil.
    @discardableResult
    func refund(
        _ amount: Decimal,
        of expense: Transaction?,
        on date: Date,
        zone: String = kolkata,
        payee: Payee? = nil,
        details: String? = nil,
    ) throws -> Transaction {
        let refund = Transaction(
            type: .income,
            amount: amount,
            date: date,
            timeZoneID: zone,
            accountID: savings.id,
            categoryID: shopping.id,
            payeeID: payee?.id,
            details: details,
            refundOfID: expense?.id,
            isRefund: true,
            createdAt: Self.now,
        )
        try repository.saveTransaction(refund)
        return refund
    }

    func transfer(_ amount: Decimal, from source: Account, to destination: Account) throws -> Transaction {
        let transfer = Transaction(
            type: .transfer,
            amount: amount,
            date: Self.date(2026, 10, 20, zone: Self.kolkata),
            timeZoneID: Self.kolkata,
            accountID: source.id,
            transferAccountID: destination.id,
            createdAt: Self.now,
        )
        try repository.saveTransaction(transfer)
        return transfer
    }

    func payee(_ name: String) throws -> Payee {
        let payee = Payee(name: name, createdAt: Self.now)
        try repository.savePayee(payee)
        return payee
    }

    func bulkEdit(_ rows: [Transaction], deviceZone: String = kolkata) -> BulkEditViewModel {
        BulkEditViewModel(
            useCases: useCases,
            transactionIDs: rows.map(\.id),
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: deviceZone)!,
            now: { Self.now },
        )
    }
}

import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence

@testable import LittleOrbitFeatures

/// Made-up ledger from Product Manager's #243 checks: today is Wed 28 Oct 2026, 18:00 in Asia/Calcutta.
@MainActor
enum AllTransactionsFixture {
    static let locale = Locale(identifier: "en_IN")
    static let zoneID = "Asia/Kolkata"
    static let zone = TimeZone(identifier: zoneID)!
    static let checkingID = UUID(uuidString: "24300000-0000-4000-8000-000000000001")!
    static let euroID = UUID(uuidString: "24300000-0000-4000-8000-000000000002")!
    static let walletID = UUID(uuidString: "24300000-0000-4000-8000-000000000003")!
    static let holidayID = UUID(uuidString: "24300000-0000-4000-8000-000000000004")!
    static let bakeryPayeeID = UUID(uuidString: "24300000-0000-4000-8000-0000000000B1")!

    static func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    static let now = date(10, 28, 18)

    static func accounts() -> [Account] {
        [
            Account(
                id: checkingID,
                name: "Everyday Checking",
                type: .checking,
                currencyCode: "USD",
                openingBalance: 500,
            ),
            Account(id: euroID, name: "Euro Card", type: .creditCard, currencyCode: "EUR", openingBalance: 0),
            Account(
                id: walletID,
                name: "Old Wallet",
                type: .cash,
                currencyCode: "INR",
                openingBalance: 1_000,
                isHidden: true,
            ),
            Account(id: holidayID, name: "Holiday Savings", type: .savings, currencyCode: "USD", openingBalance: 200),
        ]
    }

    static func transaction(
        _ type: TransactionType,
        _ amount: Decimal,
        on date: Date,
        account: UUID,
        to destination: UUID? = nil,
        payee: UUID? = nil,
        category: UUID? = nil,
        details: String? = nil,
    ) -> Transaction {
        Transaction(
            type: type,
            amount: amount,
            date: date,
            timeZoneID: zoneID,
            accountID: account,
            categoryID: category,
            payeeID: payee,
            details: details,
            transferAccountID: destination,
            createdAt: date,
        )
    }

    /// Corner Bakery −$8.40 on 27 Oct, Metro Ticket −€12.50 on 28 Oct, Tea Stall −₹60.00 on 26 Oct in the hidden
    /// Old Wallet, and a $100.00 transfer from Everyday Checking to Holiday Savings on 25 Oct.
    static let bakery = transaction(
        .expense,
        Decimal(string: "8.40")!,
        on: date(10, 27),
        account: checkingID,
        payee: bakeryPayeeID,
        category: DefaultCategoryID.food,
    )
    static let metro = transaction(
        .expense,
        Decimal(string: "12.50")!,
        on: date(10, 28),
        account: euroID,
        details: "Metro Ticket",
    )
    static let tea = transaction(.expense, 60, on: date(10, 26), account: walletID, details: "Tea Stall")
    static let move = transaction(.transfer, 100, on: date(10, 25), account: checkingID, to: holidayID)

    static func repository(_ transactions: [Transaction] = [bakery, metro, tea, move]) throws
        -> InMemoryLedgerRepository
    {
        let repository = InMemoryLedgerRepository(now: { now })
        for account in accounts() {
            try repository.saveAccount(account)
        }
        try repository.seedDefaultCategories(names: CatalogDefaultCategoryNames())
        try repository.savePayee(Payee(id: bakeryPayeeID, name: "Corner Bakery"))
        for transaction in transactions {
            try repository.saveTransaction(transaction)
        }
        return repository
    }

    static func useCases(_ repository: InMemoryLedgerRepository) -> TransactionUseCases {
        TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
    }

    /// The screen's model, loaded; registered with `updates` as its view registers it, when given.
    static func model(
        _ useCases: TransactionUseCases,
        updates: LedgerUpdates? = nil,
    ) async -> AllTransactionsViewModel {
        let model = AllTransactionsViewModel(useCases: useCases, locale: locale, timeZone: zone, now: { now })
        if let updates {
            await model.appeared(in: updates)
        } else {
            await model.load()
        }
        return model
    }

    /// Until the model shows the newest change `updates` posted: its refresh was started as the change was posted,
    /// and runs on its own (#341).
    static func settled(_ model: AllTransactionsViewModel, _ updates: LedgerUpdates) async {
        await RealTime.eventually { model.shownRevision == updates.revision && updates.refreshesRunning == 0 }
    }

    static func balance(_ accountID: UUID, _ repository: InMemoryLedgerRepository) throws -> Decimal? {
        let today = TransactionTiming.today(now, timeZone: zone)
        return try DefaultAccountHistoryUseCase(repository: repository)
            .history(of: accountID, today: today)?
            .history.currentBalance
    }

    static func balances(_ repository: InMemoryLedgerRepository) throws -> [Decimal?] {
        try [checkingID, euroID, walletID, holidayID].map { try balance($0, repository) }
    }

    /// The stored transactions by id, with `updatedAt` left out: a save or Undo stamps it, and every field the
    /// user sees or the balance uses is compared.
    static func stored(_ repository: InMemoryLedgerRepository) throws -> [Transaction] {
        try repository.transactions()
            .map { transaction in
                var copy = transaction
                copy.updatedAt = copy.createdAt
                return copy
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

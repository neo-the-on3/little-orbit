import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence

/// Made-up fixture from Tester's QA v2.1 on #22, stored in an in-memory repository.
@MainActor
enum FeatureFixture {
    static let india = Locale(identifier: "en_IN")
    /// A day after every transaction the fixtures create, so they all count as current (D21).
    static let today = CalendarDay(year: 2100, month: 1, day: 1)

    /// The real account use cases over an in-memory repository, as the App wires them over SwiftData.
    static func useCases(_ repository: InMemoryLedgerRepository) -> AccountUseCases {
        AccountUseCases(repository: repository, defaultCurrency: "INR")
    }

    static func repository(_ accounts: [Account] = all()) throws -> InMemoryLedgerRepository {
        let repository = InMemoryLedgerRepository()
        for account in accounts {
            try repository.saveAccount(account)
        }
        return repository
    }

    static func all() -> [Account] {
        [
            Account(
                name: "Everyday Savings",
                type: .savings,
                currencyCode: "INR",
                openingBalance: 25_000,
                sortOrder: 1,
            ),
            Account(
                name: "Corner Wallet",
                type: .cash,
                currencyCode: "INR",
                openingBalance: dec("1650.50"),
                sortOrder: 2,
            ),
            Account(
                name: "Travel Card",
                type: .creditCard,
                currencyCode: "INR",
                openingBalance: -30_000,
                sortOrder: 3,
                creditLimit: 100_000,
                showAvailableCredit: true,
            ),
            Account(
                name: "Long Term Fund",
                type: .investment,
                currencyCode: "INR",
                openingBalance: 20_000,
                isHidden: true,
                sortOrder: 4,
            ),
            Account(
                name: "Old Locker",
                type: .other,
                currencyCode: "INR",
                openingBalance: 5_000,
                isHidden: true,
                includeInNetWorth: false,
                sortOrder: 5,
            ),
            Account(name: "Holiday Fund", type: .savings, currencyCode: "USD", openingBalance: 1_240, sortOrder: 6),
            Account(name: "Euro Pocket", type: .cash, currencyCode: "EUR", openingBalance: 300, sortOrder: 7),
        ]
    }

    static func dec(_ text: String) -> Decimal {
        Decimal(string: text)!
    }
}

@MainActor
final class StubPlannedItems: PlannedItemsSource {
    var counts: PlannedItemCounts

    init(_ counts: PlannedItemCounts = PlannedItemCounts()) {
        self.counts = counts
    }

    func plannedItemCounts() -> PlannedItemCounts {
        counts
    }
}

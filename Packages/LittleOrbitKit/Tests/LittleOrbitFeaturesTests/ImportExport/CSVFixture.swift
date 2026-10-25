import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Made-up CSV files in `Fixtures/CSV` and the in-memory ledger they're imported into. Tester uses the same
/// files on the simulator and the Mac.
@MainActor
enum CSVFixture {
    static let india = Locale(identifier: "en_IN")
    static let zone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt

    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "Fixtures/CSV")
        )
        return try Data(contentsOf: url)
    }

    static func repository() throws -> InMemoryLedgerRepository {
        let repository = InMemoryLedgerRepository()
        try repository.saveAccount(
            Account(name: "Everyday Savings", type: .savings, currencyCode: "INR", sortOrder: 1)
        )
        try repository.saveAccount(Account(name: "Corner Wallet", type: .cash, currencyCode: "INR", sortOrder: 2))
        try repository.saveAccount(Account(name: "Travel Euros", type: .cash, currencyCode: "EUR", sortOrder: 3))
        return repository
    }

    static func account(_ name: String, in repository: InMemoryLedgerRepository) throws -> Account {
        try #require(try repository.accounts().first { $0.name == name })
    }

    final class Changes {
        var count = 0
    }

    static func model(
        _ repository: InMemoryLedgerRepository,
        changes: Changes = Changes(),
        overlayPause: @escaping @MainActor () async -> Void = { try? await Task.sleep(for: .milliseconds(32)) },
    ) -> CSVImportViewModel {
        CSVImportViewModel(
            useCases: ImportUseCases(repository: repository),
            defaultCurrency: "INR",
            locale: india,
            timeZone: zone,
            changed: { changes.count += 1 },
            overlayPause: overlayPause,
        )
    }

    static func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }
}

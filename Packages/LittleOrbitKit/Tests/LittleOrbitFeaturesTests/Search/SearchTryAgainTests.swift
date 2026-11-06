import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Try Again on a search load failure (D454 / #187 check 7). Made-up data only: Everyday Savings, Corner Bakery.
@MainActor
@Suite("Search Try Again (D454)")
struct SearchTryAgainTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private func bakeryStore() throws -> InMemoryLedgerRepository {
        let bakery = Payee(name: "Corner Bakery")
        let repository = try F.repository()
        try repository.savePayee(bakery)
        try repository.saveTransaction(
            F.expense(450, on: F.date(2026, 10, 27), payee: bakery.id)
        )
        return repository
    }

    private func model(_ search: any SearchTransactionsUseCase, query: String = "bakery")
        -> TransactionSearchViewModel
    {
        let model = TransactionSearchViewModel(
            search: search,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            defaultCurrency: "INR",
        )
        model.query = query
        return model
    }

    @Test("D454.1: Given a Debug-style read failure, When I search bakery, Then the failure shows with Try Again")
    func showsTryAgain() {
        let model = model(FailingSearch())
        model.load()
        #expect(model.failure == SearchFailure(title: "Couldn’t Load Transactions", message: "Try again."))
        #expect(model.tryAgainButton == "Try Again")
        #expect(model.sections.isEmpty)
        #expect(model.summary == nil)
        #expect(model.query == "bakery")
    }

    @Test("D454.2: Given the failure, When I turn it off and press Try Again, Then Corner Bakery −₹450.00 shows")
    func retrySucceeds() throws {
        let search = ToggleableSearch(DefaultSearchTransactionsUseCase(repository: try bakeryStore()))
        search.fails = true
        let model = model(search)
        model.load()
        #expect(model.failure != nil)
        search.fails = false
        model.retry()
        #expect(model.failure == nil)
        #expect(model.query == "bakery")
        let row = try #require(model.sections.first?.rows.first)
        #expect(row.title == "Corner Bakery")
        #expect(row.compactAmountText == "−₹450.00")
        #expect(model.summary?.countText == "1 result")
    }

    @Test(
        "D454.3: Given the failure still on, When I press Try Again, Then the failure shows again and nothing is written"
    )
    func retryStillFails() throws {
        let repository = try bakeryStore()
        let before = try repository.transactions().count
        let search = ToggleableSearch(DefaultSearchTransactionsUseCase(repository: repository))
        search.fails = true
        let model = model(search)
        model.load()
        #expect(model.failure != nil)
        #expect(search.reads == 1)
        model.retry()
        #expect(model.failure == SearchFailure(title: "Couldn’t Load Transactions", message: "Try again."))
        #expect(model.sections.isEmpty)
        #expect(model.summary == nil)
        #expect(model.query == "bakery")
        #expect(search.reads == 2)
        #expect(try repository.transactions().count == before)
    }

    @Test("D454.4: Given VoiceOver, Then Try Again reads as a button named Try Again")
    func tryAgainAccessibilityName() {
        let model = model(FailingSearch())
        #expect(model.tryAgainButton == "Try Again")
    }
}

@MainActor
private struct FailingSearch: SearchTransactionsUseCase {
    struct Failure: Error {}

    func read() throws -> TransactionSearchSnapshot {
        throw Failure()
    }
}

/// A search use case that can fail on demand, for D454 Try Again checks.
@MainActor
private final class ToggleableSearch: SearchTransactionsUseCase {
    private let base: any SearchTransactionsUseCase
    var fails = false
    private(set) var reads = 0
    struct Failure: Error {}

    init(_ base: any SearchTransactionsUseCase) {
        self.base = base
    }

    func read() throws -> TransactionSearchSnapshot {
        reads += 1
        if fails {
            throw Failure()
        }
        return try base.read()
    }
}

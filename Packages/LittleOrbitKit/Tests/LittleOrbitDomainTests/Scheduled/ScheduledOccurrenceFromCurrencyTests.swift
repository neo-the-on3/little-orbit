import Foundation
import LittleOrbitDomain
import Testing

/// Tester2's B2 copy question on #202 (6484026310), with UI Designer's fix: a save that moves From into another
/// currency, and so leaves an open occurrence From can't pay, is refused with `fromCurrencyMismatch`, which names
/// From, its currency and the currency the occurrence was set up in. A stale form keeps `receivedCurrencyMismatch`.
/// Made-up data: Top-up, ₹1,000 from Everyday Savings to the USD Wallet on the 1st, $12 received; today is 20 Oct.
@MainActor
@Suite("A save From can't pay names the currencies (#202 B2)")
struct ScheduledOccurrenceFromCurrencyTests {
    private typealias Fix = ScheduledFixture
    private static let walletID = UUID(uuidString: "5C000000-0000-4000-8000-000000000020")!
    private static let tokyoID = UUID(uuidString: "5C000000-0000-4000-8000-000000000021")!
    private static let osakaID = UUID(uuidString: "5C000000-0000-4000-8000-000000000022")!
    private static let august = Fix.day(2026, 8, 1)
    private static let september = Fix.day(2026, 9, 1)
    private static let mismatch = LedgerValidationError.fromCurrencyMismatch(
        ScheduledCurrencyMismatch(accountID: tokyoID, accountCurrencyCode: "JPY", paymentCurrencyCode: "INR")
    )

    private func scene() throws -> FakeScheduleRepository {
        var ledger = Fix.ledger
        ledger.accounts += [
            Account(id: Self.walletID, name: "USD Wallet", type: .cash, currencyCode: "USD", createdAt: Fix.created),
            Account(id: Self.tokyoID, name: "Tokyo Wallet", type: .cash, currencyCode: "JPY", createdAt: Fix.created),
            Account(id: Self.osakaID, name: "Osaka Wallet", type: .cash, currencyCode: "JPY", createdAt: Fix.created),
        ]
        let item = ScheduledItem(
            type: .transfer,
            amount: 1_000,
            destinationAmount: 12,
            receivedCurrencyCode: "USD",
            accountID: Fix.savingsID,
            transferAccountID: Self.walletID,
            details: "Top-up",
            startDay: Self.august,
            repeatRule: .monthly,
            processesAutomatically: false,
            timeZoneID: Fix.zone,
            createdAt: Fix.created,
        )
        let repository = FakeScheduleRepository(ledger)
        repository.now = Fix.created
        try repository.useCases().save(item)
        repository.now = Fix.date(2026, 10, 20)
        return repository
    }

    private func edit(
        _ key: CalendarDay,
        _ repository: FakeScheduleRepository,
        _ scope: ScheduledEditScope,
        _ change: (inout ScheduledItem) -> Void,
    ) throws {
        let current = try #require(repository.snapshot.scheduledItems.first)
        var item = current.resolved(for: key)
        item.occurrences = current.occurrences
        change(&item)
        let save = ScheduledOccurrenceSave(occurrence: key, dueDay: current.dueDay(of: key), scope: scope)
        _ = try repository.useCases().update(item, editing: save, payee: nil)
    }

    private func fromTokyo(_ item: inout ScheduledItem) {
        item.accountID = Self.tokyoID
        item.amount = 1_000
    }

    @Test("Tester2's repro: To is the Osaka Wallet (¥1,800) from 1 Sep; All future from 1 Aug from the Tokyo Wallet")
    func testersRepro() throws {
        let repository = try scene()
        try edit(Self.september, repository, .allFuture) {
            $0.transferAccountID = Self.osakaID
            $0.destinationAmount = 1_800
            $0.receivedCurrencyCode = "JPY"
        }
        try edit(Self.september, repository, .thisOccurrence) { $0.amount = Decimal(string: "1000.50")! }
        let before = repository.snapshot
        #expect(throws: Self.mismatch) {
            try edit(Self.august, repository, .allFuture, fromTokyo)
        }
        #expect(repository.snapshot == before, "Nothing written")
    }

    @Test("1 Sep owns ₹1,000.50: All future from 1 Aug, or a whole-item save, from the Tokyo Wallet is refused")
    func ownAmountFromYen() throws {
        let repository = try scene()
        try edit(Self.september, repository, .thisOccurrence) { $0.amount = Decimal(string: "1000.50")! }
        let before = repository.snapshot
        #expect(throws: Self.mismatch) {
            try edit(Self.august, repository, .allFuture, fromTokyo)
        }
        var item = try #require(repository.snapshot.scheduledItems.first)
        fromTokyo(&item)
        #expect(throws: Self.mismatch, "A whole-item save says the same") {
            try repository.useCases().save(item)
        }
        #expect(repository.snapshot == before, "Nothing written")
    }

    @Test("A stale form, its own received amount left in after From moved to the Osaka Wallet: the stale error")
    func staleFormKeepsStaleError() throws {
        let repository = try scene()
        try edit(Self.september, repository, .allFuture) {
            $0.transferAccountID = Self.osakaID
            $0.destinationAmount = 1_800
            $0.receivedCurrencyCode = "JPY"
        }
        let before = repository.snapshot
        // From and To both in yen with ¥1,800 still received: the form drops Received there, so this one is stale.
        #expect(throws: LedgerValidationError.receivedCurrencyMismatch) {
            try edit(Self.september, repository, .allFuture) { $0.accountID = Self.tokyoID }
        }
        #expect(throws: LedgerValidationError.receivedCurrencyMismatch) {
            try edit(Self.september, repository, .thisOccurrence) { $0.accountID = Self.tokyoID }
        }
        #expect(repository.snapshot == before, "Nothing written")
    }
}

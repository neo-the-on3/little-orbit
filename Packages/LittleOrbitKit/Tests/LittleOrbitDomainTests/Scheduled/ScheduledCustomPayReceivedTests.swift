import Foundation
import LittleOrbitDomain
import Testing

/// #207's received currency on #201's custom Pay (second-lander gate, Tech Architect 5681779824): a custom Pay of a
/// transfer between currencies records the amount received it was given, with To's currency code, on the payment and,
/// with "Also change future occurrences", on the schedule; never the item's old amount received. A code that isn't
/// To's currency is refused, and nothing is written. Made-up data.
@MainActor
@Suite("Custom Pay of a transfer between currencies (#207 B1 on #201)")
struct ScheduledCustomPayReceivedTests {
    private typealias Fix = ScheduledFixture
    private static let walletID = UUID(uuidString: "5C000000-0000-4000-8000-000000000020")!
    private static let cardID = UUID(uuidString: "5C000000-0000-4000-8000-000000000021")!

    private static var ledger: LedgerSnapshot {
        var ledger = Fix.ledger
        ledger.accounts.append(
            Account(id: walletID, name: "USD Wallet", type: .cash, currencyCode: "USD", createdAt: Fix.created)
        )
        ledger.accounts.append(
            Account(
                id: cardID,
                name: "USD Card",
                type: .cash,
                currencyCode: "USD",
                sortOrder: 9,
                createdAt: Fix.created,
            )
        )
        return ledger
    }

    /// ₹1,000 a month from Savings, received as $12 in the USD Wallet, from 5 Aug; paid by hand.
    private static let wallet = ScheduledItem(
        type: .transfer,
        amount: 1_000,
        destinationAmount: 12,
        receivedCurrencyCode: "USD",
        accountID: Fix.savingsID,
        transferAccountID: walletID,
        details: "Fund USD Wallet",
        startDay: Fix.day(2026, 8, 5),
        timeZoneID: Fix.zone,
        createdAt: Fix.created,
    )

    private func repository() throws -> FakeScheduleRepository {
        let repository = FakeScheduleRepository(Self.ledger)
        repository.now = Fix.created
        try repository.useCases().save(Self.wallet)
        repository.now = Fix.date(2026, 10, 20)
        return repository
    }

    private func custom(
        _ amount: Decimal,
        received: Decimal?,
        code: String? = "USD",
        future: Bool = false,
        from accountID: UUID = Fix.savingsID,
    ) -> ScheduledCustomPayment {
        ScheduledCustomPayment(
            amount: amount,
            accountID: accountID,
            categoryID: nil,
            changesFutureOccurrences: future,
            receivedAmount: received,
            receivedCurrencyCode: code,
        )
    }

    private func pay(_ custom: ScheduledCustomPayment, in repository: FakeScheduleRepository) throws
        -> ScheduledSettlementChange?
    {
        try repository.useCases()
            .pay(itemID: Self.wallet.id, occurrence: Fix.day(2026, 8, 5), on: Fix.day(2026, 8, 6), custom: custom)
    }

    @Test("₹2,000 received as $24: the payment records $24, and the schedule keeps ₹1,000 and $12")
    func thisOccurrence() throws {
        let repository = try repository()
        let change = try #require(try pay(custom(2_000, received: 24), in: repository))
        let paid = try #require(change.transaction)
        #expect(paid.amount == 2_000)
        #expect(paid.destinationAmount == 24, "Never the old $12")
        let stored = try #require(repository.snapshot.scheduledItems.first)
        #expect(stored.amount == 1_000)
        #expect(stored.destinationAmount == 12)
        #expect(stored.receivedCurrencyCode == "USD")
        #expect(LedgerBook.receivedCurrencyIsCurrent(of: stored, in: repository.snapshot))
    }

    @Test("Also change future occurrences: the schedule takes $24 and To's code, so the next posting succeeds")
    func futureOccurrences() throws {
        let repository = try repository()
        _ = try #require(try pay(custom(2_000, received: 24, future: true), in: repository))
        let stored = try #require(repository.snapshot.scheduledItems.first)
        #expect(stored.amount == 2_000)
        #expect(stored.destinationAmount == 24)
        #expect(stored.receivedCurrencyCode == "USD")
        #expect(LedgerBook.receivedCurrencyIsCurrent(of: stored, in: repository.snapshot))
        let next = try #require(
            try repository.useCases().payNow(itemID: Self.wallet.id, occurrence: Fix.day(2026, 9, 5))
        )
        #expect(next.amount == 2_000)
        #expect(next.destinationAmount == 24)
    }

    @Test("A received amount in another code than To's is refused, and nothing is written", arguments: [false, true])
    func mismatchRefused(future: Bool) throws {
        let repository = try repository()
        let before = repository.snapshot
        #expect(throws: LedgerValidationError.receivedCurrencyMismatch) {
            try pay(custom(2_000, received: 24, code: "EUR", future: future), in: repository)
        }
        #expect(throws: LedgerValidationError.receivedCurrencyMismatch) {
            try pay(custom(2_000, received: 24, code: nil, future: future), in: repository)
        }
        #expect(repository.snapshot == before)
    }

    @Test("No amount received on a transfer between currencies: refused, never posted with the old $12")
    func missingReceivedRefused() throws {
        let repository = try repository()
        let before = repository.snapshot
        #expect(throws: (any Error).self) { try pay(custom(2_000, received: nil, code: nil), in: repository) }
        #expect(repository.snapshot == before)
    }

    // MARK: Undo and Redo with future occurrences (Tech Architect, review 5684398084)

    private func revert(_ result: ScheduledSettlementRevert) throws -> ScheduledSettlementChange {
        guard case .reverted(let left) = result else {
            Issue.record("Expected a revert, got \(result)")
            throw LedgerValidationError.missingScheduledItem
        }
        return left
    }

    private func schedule(_ repository: FakeScheduleRepository) throws -> ScheduledItem {
        try #require(repository.snapshot.scheduledItems.first)
    }

    /// To, the USD Wallet, moved to EUR past the store's currency lock, as a restored backup could leave it.
    private func moveWallet(_ repository: FakeScheduleRepository) throws {
        let index = try #require(repository.snapshot.accounts.firstIndex { $0.id == Self.walletID })
        repository.snapshot.accounts[index].currencyCode = "EUR"
    }

    @Test("The repro: ₹2,000 received as $24 with future on; Undo puts back ₹1,000 and $12, Redo $24 again")
    func undoRedoRestoresReceived() throws {
        let repository = try repository()
        let paid = try #require(try pay(custom(2_000, received: 24, future: true), in: repository))
        let undone = try revert(try repository.unsettleScheduledOccurrence(paid))
        var stored = try schedule(repository)
        #expect(stored.amount == 1_000)
        #expect(stored.destinationAmount == 12, "Never the custom payment's $24")
        #expect(stored.receivedCurrencyCode == "USD")
        #expect(repository.snapshot.transactions.isEmpty)
        let redone = try revert(try repository.resettleScheduledOccurrence(undone))
        stored = try schedule(repository)
        #expect(stored.amount == 2_000)
        #expect(stored.destinationAmount == 24)
        #expect(stored.receivedCurrencyCode == "USD")
        #expect(repository.snapshot.transactions.first?.destinationAmount == 24)
        _ = try revert(try repository.unsettleScheduledOccurrence(redone))
        stored = try schedule(repository)
        #expect(stored.amount == 1_000 && stored.destinationAmount == 12 && stored.receivedCurrencyCode == "USD")
    }

    @Test(
        "Paid from a USD account with future on, so nothing is received; Undo puts back $12 and USD, Redo clears both"
    )
    func undoRestoresReceivedCurrency() throws {
        let repository = try repository()
        let paid = try #require(
            try pay(custom(50, received: nil, code: nil, future: true, from: Self.cardID), in: repository)
        )
        var stored = try schedule(repository)
        #expect(stored.destinationAmount == nil && stored.receivedCurrencyCode == nil)
        let undone = try revert(try repository.unsettleScheduledOccurrence(paid))
        stored = try schedule(repository)
        #expect(stored.accountID == Fix.savingsID)
        #expect(stored.destinationAmount == 12)
        #expect(stored.receivedCurrencyCode == "USD")
        #expect(LedgerBook.receivedCurrencyIsCurrent(of: stored, in: repository.snapshot))
        _ = try revert(try repository.resettleScheduledOccurrence(undone))
        stored = try schedule(repository)
        #expect(stored.accountID == Self.cardID)
        #expect(stored.destinationAmount == nil && stored.receivedCurrencyCode == nil)
    }

    @Test("To moved from USD to EUR since: Undo of the future-on Pay is stale and writes nothing")
    func undoStaleWhenToMoved() throws {
        let repository = try repository()
        let paid = try #require(try pay(custom(2_000, received: 24, future: true), in: repository))
        try moveWallet(repository)
        let before = repository.snapshot
        #expect(try repository.unsettleScheduledOccurrence(paid) == .stale(.scheduledItemChanged(Self.wallet.id)))
        #expect(repository.snapshot == before)
    }

    @Test("To moved from USD to EUR after Undo: Redo of the future-on Pay is stale and writes nothing")
    func redoStaleWhenToMoved() throws {
        let repository = try repository()
        let paid = try #require(try pay(custom(2_000, received: 24, future: true), in: repository))
        let undone = try revert(try repository.unsettleScheduledOccurrence(paid))
        try moveWallet(repository)
        let before = repository.snapshot
        #expect(try repository.resettleScheduledOccurrence(undone) == .stale(.scheduledItemChanged(Self.wallet.id)))
        #expect(repository.snapshot == before)
    }
}

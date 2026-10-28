import Foundation
import LittleOrbitDomain
import Testing

/// #207 t1: the received amount's currency goes with the received amount. Whenever a save leaves an item with no
/// received amount (To back in From's currency, or no longer a transfer), the store clears
/// `receivedCurrencyCode` too, on a new item and on an edit, so a stale code is never kept.
@MainActor
@Suite("Clearing Received clears its currency at the store (#207 t1)")
struct ScheduledReceivedCurrencyClearTests {
    private typealias Fix = ScheduledFixture
    private static let walletID = UUID(uuidString: "5C000000-0000-4000-8000-000000000020")!

    private static var ledger: LedgerSnapshot {
        var ledger = Fix.ledger
        ledger.accounts.append(
            Account(id: walletID, name: "USD Wallet", type: .cash, currencyCode: "USD", createdAt: Fix.created)
        )
        return ledger
    }

    /// ₹1,000 from Everyday Savings to the USD Wallet, received $12.
    private func share() -> ScheduledItem {
        ScheduledItem(
            type: .transfer,
            amount: 1_000,
            destinationAmount: 12,
            receivedCurrencyCode: "USD",
            accountID: Fix.savingsID,
            transferAccountID: Self.walletID,
            details: "Rent Share",
            startDay: Fix.day(2026, 11, 5),
            processesAutomatically: false,
            timeZoneID: Fix.zone,
            createdAt: Fix.created,
        )
    }

    private func repository() -> FakeScheduleRepository {
        let repository = FakeScheduleRepository(Self.ledger)
        repository.now = Fix.created
        return repository
    }

    private func stored(_ id: UUID, in repository: FakeScheduleRepository) throws -> ScheduledItem {
        try #require(repository.snapshot.scheduledItems.first { $0.id == id })
    }

    @Test("A new transfer saved with no received amount keeps no received currency, even if one was given")
    func newItemWithoutReceived() throws {
        let repository = repository()
        var item = share()
        item.transferAccountID = Fix.fundID
        item.destinationAmount = nil
        try repository.useCases().save(item)
        let saved = try stored(item.id, in: repository)
        #expect(saved.destinationAmount == nil)
        #expect(saved.receivedCurrencyCode == nil)
    }

    @Test("Editing To back to From's currency clears Received and its currency")
    func editToSameCurrency() throws {
        let repository = repository()
        let item = share()
        try repository.useCases().save(item)
        #expect(try stored(item.id, in: repository).receivedCurrencyCode == "USD")
        var edit = try stored(item.id, in: repository)
        edit.transferAccountID = Fix.fundID
        edit.destinationAmount = nil
        _ = try repository.useCases().update(edit, payee: nil)
        let saved = try stored(item.id, in: repository)
        #expect(saved.transferAccountID == Fix.fundID)
        #expect(saved.destinationAmount == nil)
        #expect(saved.receivedCurrencyCode == nil, "The old USD code goes with the received amount")
    }

    @Test("Editing a cross-currency transfer into an expense clears Received and its currency")
    func editToExpense() throws {
        let repository = repository()
        let item = share()
        try repository.useCases().save(item)
        var edit = try stored(item.id, in: repository)
        edit.type = .expense
        edit.categoryID = Fix.housingID
        _ = try repository.useCases().update(edit, payee: nil)
        let saved = try stored(item.id, in: repository)
        #expect(saved.type == .expense && saved.transferAccountID == nil)
        #expect(saved.destinationAmount == nil)
        #expect(saved.receivedCurrencyCode == nil)
    }

    @Test("A save that keeps Received keeps its currency")
    func keptReceivedKeepsCode() throws {
        let repository = repository()
        let item = share()
        try repository.useCases().save(item)
        var edit = try stored(item.id, in: repository)
        edit.details = "Rent Share, November"
        _ = try repository.useCases().update(edit, payee: nil)
        let saved = try stored(item.id, in: repository)
        #expect(saved.destinationAmount == 12 && saved.receivedCurrencyCode == "USD")
    }
}

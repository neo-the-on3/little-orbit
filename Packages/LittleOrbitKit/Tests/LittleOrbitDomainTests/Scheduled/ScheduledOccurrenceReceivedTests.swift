import Foundation
import LittleOrbitDomain
import Testing

/// An occurrence edit of a transfer between currencies (#207 B1 with #202): the amount received and the currency it
/// was entered in go with the To account. "This occurrence only" keeps them as the occurrence's own, so the item and
/// its other occurrences keep theirs; "All future occurrences" gives them to the item. A received amount whose code
/// isn't the occurrence's To currency is refused, and nothing is written. Made-up data.
@MainActor
@Suite("Occurrence edits of a transfer between currencies (#207 B1, D45)")
struct ScheduledOccurrenceReceivedTests {
    private typealias Fix = ScheduledFixture
    private static let walletID = UUID(uuidString: "5C000000-0000-4000-8000-000000000010")!
    private static let yenID = UUID(uuidString: "5C000000-0000-4000-8000-000000000011")!
    private static let december = Fix.day(2026, 12, 5)
    private static let november = Fix.day(2026, 11, 5)

    /// ₹1,000 to the USD Wallet on the 5th, $12 received, saved on 1 Jul and opened on 20 Oct.
    private func scene() throws -> (FakeScheduleRepository, ScheduledItem) {
        var ledger = Fix.ledger
        ledger.accounts += [
            Account(id: Self.walletID, name: "USD Wallet", type: .cash, currencyCode: "USD", createdAt: Fix.created),
            Account(id: Self.yenID, name: "Tokyo Wallet", type: .cash, currencyCode: "JPY", createdAt: Fix.created),
        ]
        let item = ScheduledItem(
            type: .transfer,
            amount: 1_000,
            destinationAmount: 12,
            receivedCurrencyCode: "USD",
            accountID: Fix.savingsID,
            transferAccountID: Self.walletID,
            details: "Fund USD Wallet",
            startDay: Fix.day(2026, 8, 5),
            repeatRule: .monthly,
            processesAutomatically: false,
            timeZoneID: Fix.zone,
            createdAt: Fix.created,
        )
        let repository = FakeScheduleRepository(ledger)
        repository.now = Fix.created
        try repository.useCases().save(item)
        repository.now = Fix.date(2026, 10, 20)
        return (repository, item)
    }

    private func stored(_ repository: FakeScheduleRepository) throws -> ScheduledItem {
        try #require(repository.snapshot.scheduledItems.first)
    }

    private func edit(
        _ key: CalendarDay = december,
        in repository: FakeScheduleRepository,
        scope: ScheduledEditScope,
        _ change: (inout ScheduledItem) -> Void,
    ) throws {
        let current = try stored(repository)
        var item = current.resolved(for: key)
        item.occurrences = current.occurrences
        change(&item)
        let save = ScheduledOccurrenceSave(occurrence: key, dueDay: current.dueDay(of: key), scope: scope)
        _ = try repository.useCases().update(item, editing: save, payee: nil)
    }

    private func toYen(_ item: inout ScheduledItem) {
        item.transferAccountID = Self.yenID
        item.destinationAmount = 1_800
        item.receivedCurrencyCode = "JPY"
    }

    @Test("This occurrence only, To the Tokyo Wallet with ¥1,800: only 5 Dec takes them, and records them")
    func thisOccurrenceTo() throws {
        let (repository, _) = try scene()
        try edit(in: repository, scope: .thisOccurrence, toYen)
        let item = try stored(repository)
        #expect(item.transferAccountID == Self.walletID)
        #expect(item.destinationAmount == 12)
        #expect(item.receivedCurrencyCode == "USD")
        let december = item.resolved(for: Self.december)
        #expect(december.transferAccountID == Self.yenID)
        #expect(december.destinationAmount == 1_800)
        #expect(december.receivedCurrencyCode == "JPY")
        #expect(LedgerBook.receivedCurrencyIsCurrent(of: december, in: repository.snapshot))
        let november = item.resolved(for: Self.november)
        #expect(november.transferAccountID == Self.walletID)
        #expect(november.destinationAmount == 12)
        repository.now = Fix.date(2026, 12, 6)
        let paid = try #require(
            try repository.useCases().pay(itemID: item.id, occurrence: Self.december, on: Self.december, custom: nil)
        )
        #expect(paid.transaction?.transferAccountID == Self.yenID)
        #expect(paid.transaction?.destinationAmount == 1_800)
    }

    @Test("This occurrence only, $13 received instead of $12: only 5 Dec takes it")
    func thisOccurrenceReceived() throws {
        let (repository, _) = try scene()
        try edit(in: repository, scope: .thisOccurrence) { $0.destinationAmount = 13 }
        let item = try stored(repository)
        #expect(item.destinationAmount == 12)
        #expect(item.resolved(for: Self.december).destinationAmount == 13)
        #expect(item.resolved(for: Self.december).receivedCurrencyCode == "USD")
        #expect(item.resolved(for: Self.november).destinationAmount == 12)
    }

    @Test("All future occurrences, To the Tokyo Wallet: the item takes ¥1,800 in JPY; 5 Nov keeps $12 (S58)")
    func allFutureTo() throws {
        let (repository, _) = try scene()
        try edit(in: repository, scope: .allFuture, toYen)
        let item = try stored(repository)
        #expect(item.transferAccountID == Self.yenID)
        #expect(item.destinationAmount == 1_800)
        #expect(item.receivedCurrencyCode == "JPY")
        let november = item.resolved(for: Self.november)
        #expect(november.transferAccountID == Self.walletID)
        #expect(november.destinationAmount == 12)
        #expect(november.receivedCurrencyCode == "USD")
    }

    @Test("To the Tokyo Wallet with the received amount still in USD: refused, and nothing is written")
    func staleCodeRefused() throws {
        let (repository, _) = try scene()
        let before = repository.snapshot
        for scope in ScheduledEditScope.allCases {
            #expect(throws: LedgerValidationError.receivedCurrencyMismatch) {
                try edit(in: repository, scope: scope) { $0.transferAccountID = Self.yenID }
            }
            #expect(repository.snapshot == before)
        }
    }

    @Test("A backup keeps an occurrence's own amount received and its currency")
    func backupRoundTrip() throws {
        let (repository, _) = try scene()
        try edit(in: repository, scope: .thisOccurrence, toYen)
        let record = try #require(try stored(repository).occurrence(on: Self.december))
        let decoded = try JSONDecoder().decode(ScheduledOccurrence.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
        #expect(decoded.edit?.destinationAmount == 1_800)
        #expect(decoded.edit?.receivedCurrencyCode == "JPY")
    }

    @Test("Its own To account deleted, 5 Dec follows the item's To and amount received again (#202 B1)")
    func missingToDropsReceived() throws {
        let (repository, _) = try scene()
        try edit(in: repository, scope: .thisOccurrence, toYen)
        var ledger = repository.snapshot
        let index = try #require(ledger.accounts.firstIndex { $0.id == Self.yenID })
        ledger.accounts[index].deletedAt = Fix.date(2026, 10, 21)
        let item = try #require(LedgerBook.withoutMissingEditReferences(in: ledger).scheduledItems.first)
        let december = item.resolved(for: Self.december)
        #expect(december.transferAccountID == Self.walletID)
        #expect(december.destinationAmount == 12)
        #expect(LedgerBook.receivedCurrencyIsCurrent(of: december, in: ledger))
    }
}

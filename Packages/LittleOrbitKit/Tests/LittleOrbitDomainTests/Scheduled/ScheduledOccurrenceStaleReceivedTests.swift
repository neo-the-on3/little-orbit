import Foundation
import LittleOrbitDomain
import Testing

/// Tech Architect's B2 on #202 (review 5687750600): no save leaves an open occurrence that Pay Now refuses. The amount
/// received goes with To (D340.15, D368.2), so a save that changes the To or From currency an occurrence resolves to
/// drops that occurrence's own received amount where it no longer reads, and the occurrence follows the item's again.
/// Every open occurrence is then checked as it would record, and a save that would still leave one unpayable is
/// refused with nothing written. Made-up data: ₹1,000 to the USD Wallet on the 5th, $12 received.
@MainActor
@Suite("Saves never leave an occurrence Pay Now refuses (#202 B2)")
struct ScheduledOccurrenceStaleReceivedTests {
    private typealias Fix = ScheduledFixture
    private static let walletID = UUID(uuidString: "5C000000-0000-4000-8000-000000000010")!
    private static let yenID = UUID(uuidString: "5C000000-0000-4000-8000-000000000011")!
    private static let cardID = UUID(uuidString: "5C000000-0000-4000-8000-000000000012")!
    private static let yenSavingsID = UUID(uuidString: "5C000000-0000-4000-8000-000000000013")!
    private static let december = Fix.day(2026, 12, 5)
    private static let november = Fix.day(2026, 11, 5)

    private func scene() throws -> FakeScheduleRepository {
        var ledger = Fix.ledger
        ledger.accounts += [
            Account(id: Self.walletID, name: "USD Wallet", type: .cash, currencyCode: "USD", createdAt: Fix.created),
            Account(id: Self.yenID, name: "Tokyo Wallet", type: .cash, currencyCode: "JPY", createdAt: Fix.created),
            Account(id: Self.cardID, name: "USD Card", type: .cash, currencyCode: "USD", createdAt: Fix.created),
            Account(
                id: Self.yenSavingsID,
                name: "Yen Savings",
                type: .savings,
                currencyCode: "JPY",
                createdAt: Fix.created,
            ),
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
        return repository
    }

    private func stored(_ repository: FakeScheduleRepository) throws -> ScheduledItem {
        try #require(repository.snapshot.scheduledItems.first)
    }

    private func edit(
        _ key: CalendarDay,
        _ repository: FakeScheduleRepository,
        _ scope: ScheduledEditScope,
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

    /// From the USD Card, so From and To are both in USD: a transfer in one currency, with no amount received.
    private func fromCard(_ item: inout ScheduledItem) {
        item.accountID = Self.cardID
        item.amount = 12
        item.destinationAmount = nil
        item.receivedCurrencyCode = nil
    }

    /// 5 Dec, paid on 6 Dec with Pay Now: what it records, or the error that refuses it.
    private func payDecember(_ repository: FakeScheduleRepository) throws -> Transaction? {
        repository.now = Fix.date(2026, 12, 6)
        let item = try stored(repository)
        return try repository.useCases()
            .pay(itemID: item.id, occurrence: Self.december, on: Self.december, custom: nil)?
            .transaction
    }

    private func expectPayable(_ repository: FakeScheduleRepository) throws {
        let item = try stored(repository)
        for record in item.occurrences where record.deletedAt == nil && !record.outcome.isSettled {
            #expect(
                LedgerBook.receivedCurrencyIsCurrent(of: item.resolved(for: record.day), in: repository.snapshot),
                "\(record.day) is left with a received amount Pay Now refuses",
            )
        }
    }

    @Test("Tech Architect's repro: 5 Dec owns $13; All future from 5 Nov to the Tokyo Wallet: 5 Dec records ¥1,800")
    func allFutureToDropsStaleReceived() throws {
        let repository = try scene()
        try edit(Self.december, repository, .thisOccurrence) { $0.destinationAmount = 13 }
        try edit(Self.november, repository, .allFuture, toYen)
        try expectPayable(repository)
        let item = try stored(repository)
        #expect(item.edit(for: Self.december)?.has(.received) != true, "5 Dec's own $13 went with the USD Wallet")
        let december = item.resolved(for: Self.december)
        #expect(december.transferAccountID == Self.yenID)
        #expect(december.destinationAmount == 1_800 && december.receivedCurrencyCode == "JPY")
        let paid = try #require(try payDecember(repository))
        #expect(paid.transferAccountID == Self.yenID && paid.destinationAmount == 1_800)
    }

    @Test("All future from 5 Nov moves From to the USD Card, into To's currency: 5 Dec's own $13 is dropped too")
    func allFutureFromDropsStaleReceived() throws {
        let repository = try scene()
        try edit(Self.december, repository, .thisOccurrence) { $0.destinationAmount = 13 }
        try edit(Self.november, repository, .allFuture, fromCard)
        try expectPayable(repository)
        let paid = try #require(try payDecember(repository))
        #expect(paid.accountID == Self.cardID && paid.transferAccountID == Self.walletID)
        #expect(paid.amount == 12 && paid.destinationAmount == nil)
    }

    @Test("A received amount that still reads is kept: To the USD Card, also in USD, and 5 Dec keeps $13 (D111)")
    func receivedThatStillReadsIsKept() throws {
        let repository = try scene()
        try edit(Self.december, repository, .thisOccurrence) { $0.destinationAmount = 13 }
        try edit(Self.november, repository, .allFuture) { $0.transferAccountID = Self.cardID }
        let december = try stored(repository).resolved(for: Self.december)
        #expect(december.transferAccountID == Self.cardID)
        #expect(december.destinationAmount == 13 && december.receivedCurrencyCode == "USD")
        let paid = try #require(try payDecember(repository))
        #expect(paid.destinationAmount == 13)
    }

    @Test("5 Dec with its own USD Card and $13 keeps both when All future moves To to the Tokyo Wallet (D111)")
    func ownToKeepsItsReceived() throws {
        let repository = try scene()
        try edit(Self.december, repository, .thisOccurrence) {
            $0.transferAccountID = Self.cardID
            $0.destinationAmount = 13
        }
        try edit(Self.november, repository, .allFuture, toYen)
        try expectPayable(repository)
        let paid = try #require(try payDecember(repository))
        #expect(paid.transferAccountID == Self.cardID && paid.destinationAmount == 13)
    }

    @Test("A whole-item save to the Tokyo Wallet drops 5 Dec's own $13 the same way")
    func wholeItemSaveDropsStaleReceived() throws {
        let repository = try scene()
        try edit(Self.december, repository, .thisOccurrence) { $0.destinationAmount = 13 }
        var item = try stored(repository)
        toYen(&item)
        try repository.useCases().save(item)
        try expectPayable(repository)
        let paid = try #require(try payDecember(repository))
        #expect(paid.transferAccountID == Self.yenID && paid.destinationAmount == 1_800)
    }

    @Test("Custom Pay of 5 Nov from the USD Card with Also change future occurrences: 5 Dec's own $13 is dropped")
    func customPayChangingFutureDropsStaleReceived() throws {
        let repository = try scene()
        try edit(Self.december, repository, .thisOccurrence) { $0.destinationAmount = 13 }
        repository.now = Fix.date(2026, 11, 6)
        let item = try stored(repository)
        let custom = ScheduledCustomPayment(
            amount: 12,
            accountID: Self.cardID,
            categoryID: nil,
            changesFutureOccurrences: true,
        )
        _ = try repository.useCases()
            .pay(itemID: item.id, occurrence: Self.november, on: Self.november, custom: custom)
        try expectPayable(repository)
        let paid = try #require(try payDecember(repository))
        #expect(paid.accountID == Self.cardID && paid.destinationAmount == nil)
    }

    @Test("All future from 5 Nov moves From to Yen Savings while 5 Dec owns ₹1,000.50: refused, nothing written")
    func unpayableOccurrenceRefused() throws {
        let repository = try scene()
        try edit(Self.december, repository, .thisOccurrence) { $0.amount = Decimal(string: "1000.50")! }
        let before = repository.snapshot
        #expect(throws: (any Error).self) {
            try edit(Self.november, repository, .allFuture) { $0.accountID = Self.yenSavingsID }
        }
        #expect(repository.snapshot == before)
        var item = try stored(repository)
        item.accountID = Self.yenSavingsID
        #expect(throws: (any Error).self, "A whole-item save is checked the same way") {
            try repository.useCases().save(item)
        }
        #expect(repository.snapshot == before)
    }

    @Test("This occurrence only on 5 Nov to the Tokyo Wallet leaves 5 Dec's own $13 as it was, and payable")
    func thisOccurrenceLeavesOthers() throws {
        let repository = try scene()
        try edit(Self.december, repository, .thisOccurrence) { $0.destinationAmount = 13 }
        try edit(Self.november, repository, .thisOccurrence, toYen)
        try expectPayable(repository)
        let paid = try #require(try payDecember(repository))
        #expect(paid.transferAccountID == Self.walletID && paid.destinationAmount == 13)
    }

    @Test("This occurrence only on 5 Dec from the USD Card with its own $13 left in: refused, nothing written")
    func thisOccurrenceStaleFormRefused() throws {
        let repository = try scene()
        try edit(Self.december, repository, .thisOccurrence) { $0.destinationAmount = 13 }
        let before = repository.snapshot
        // The form drops Received when From moves into To's currency; one that didn't is stale, and saves nothing.
        #expect(throws: LedgerValidationError.receivedCurrencyMismatch) {
            try edit(Self.december, repository, .thisOccurrence) {
                $0.accountID = Self.cardID
                $0.amount = 12
            }
        }
        #expect(repository.snapshot == before)
        try edit(Self.december, repository, .thisOccurrence, fromCard)
        try expectPayable(repository)
        let paid = try #require(try payDecember(repository))
        #expect(paid.accountID == Self.cardID && paid.amount == 12 && paid.destinationAmount == nil)
    }

    @Test("This occurrence only, 5 Dec back to the USD Wallet with its own ¥1,800 left: refused, never the item's $12")
    func thisOccurrenceKeepsWhatTheFormSaved() throws {
        let repository = try scene()
        try edit(Self.december, repository, .thisOccurrence, toYen)
        let before = repository.snapshot
        #expect(throws: LedgerValidationError.receivedCurrencyMismatch) {
            try edit(Self.december, repository, .thisOccurrence) { $0.transferAccountID = Self.walletID }
        }
        #expect(repository.snapshot == before)
    }
}

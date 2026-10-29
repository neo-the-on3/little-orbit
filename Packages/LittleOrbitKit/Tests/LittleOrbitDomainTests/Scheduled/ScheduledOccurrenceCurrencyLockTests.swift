import Foundation
import LittleOrbitDomain
import Testing

/// Tech Architect's B3 on #202 (review 5688424445): an account that only an occurrence's own values use, as its own
/// From or To, keeps its currency like one the item itself uses (D381.3, D410.1, D412). Settled occurrences count
/// too, since Undo Pay or Undo Skip brings their values back. Made-up data.
@MainActor
@Suite("Occurrences' own accounts lock their currency (#202 B3)")
struct ScheduledOccurrenceCurrencyLockTests {
    private typealias Fix = ScheduledFixture
    private static let walletID = UUID(uuidString: "5C000000-0000-4000-8000-000000000010")!
    private static let yenID = UUID(uuidString: "5C000000-0000-4000-8000-000000000011")!
    private static let cardID = UUID(uuidString: "5C000000-0000-4000-8000-000000000012")!
    private static let december = Fix.day(2026, 12, 5)
    private static let november = Fix.day(2026, 11, 5)

    /// Accounts with no transactions: the USD Wallet, the Tokyo Wallet (JPY) and the USD Card. With `transfer`, ₹1,000
    /// to the USD Wallet on the 5th with $12 received; else Rent, ₹25,000 from Everyday Savings on the 5th.
    private func scene(transfer: Bool) throws -> FakeScheduleRepository {
        var ledger = Fix.ledger
        ledger.accounts += [
            Account(id: Self.walletID, name: "USD Wallet", type: .cash, currencyCode: "USD", createdAt: Fix.created),
            Account(id: Self.yenID, name: "Tokyo Wallet", type: .cash, currencyCode: "JPY", createdAt: Fix.created),
            Account(id: Self.cardID, name: "USD Card", type: .cash, currencyCode: "USD", createdAt: Fix.created),
        ]
        let item =
            transfer
            ? ScheduledItem(
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
            : Fix.rent(start: Fix.day(2026, 8, 5), automatic: false)
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
        _ scope: ScheduledEditScope = .thisOccurrence,
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

    /// The store's account save with `id` moved to EUR.
    private func moveToEuro(_ id: UUID, in repository: FakeScheduleRepository) throws {
        var account = try #require(repository.snapshot.accounts.first { $0.id == id })
        account.currencyCode = "EUR"
        _ = try LedgerBook.savingAccount(account, in: repository.snapshot, now: Fix.date(2026, 10, 21))
    }

    @Test("Tech Architect's repro: 5 Dec's own To is the Tokyo Wallet with ¥1,800; moving it to EUR is refused")
    func ownToLocksStore() throws {
        let repository = try scene(transfer: true)
        try edit(Self.december, repository, .thisOccurrence, toYen)
        #expect(CurrencyLock.scheduledAccountIDs(in: repository.snapshot).contains(Self.yenID))
        #expect(throws: LedgerValidationError.currencyLocked) { try moveToEuro(Self.yenID, in: repository) }
        #expect(!CurrencyLock.scheduledAccountIDs(in: repository.snapshot).contains(Self.cardID))
        _ = try moveToEuro(Self.cardID, in: repository)
    }

    @Test("Rent's 5 Dec is paid from its own USD Card; moving the card to EUR is refused")
    func ownFromLocksStore() throws {
        let repository = try scene(transfer: false)
        try edit(Self.december, repository) {
            $0.accountID = Self.cardID
            $0.amount = 300
        }
        #expect(CurrencyLock.scheduledAccountIDs(in: repository.snapshot).contains(Self.cardID))
        #expect(throws: LedgerValidationError.currencyLocked) { try moveToEuro(Self.cardID, in: repository) }
    }

    @Test("A skipped occurrence with its own To still locks it, as Undo Skip brings it back")
    func settledOccurrenceLocks() throws {
        let repository = try scene(transfer: true)
        try edit(Self.november, repository, .thisOccurrence, toYen)
        let item = try stored(repository)
        _ = try repository.useCases().skip(itemID: item.id, occurrence: Self.november)
        #expect(try stored(repository).isSettled(Self.november))
        #expect(repository.snapshot.transactions.isEmpty)
        #expect(throws: LedgerValidationError.currencyLocked) { try moveToEuro(Self.yenID, in: repository) }
    }

    @Test("Only the fields an occurrence sets count: one with only its own amount locks nothing more")
    func onlySetFieldsCount() throws {
        let repository = try scene(transfer: true)
        try edit(Self.december, repository) { $0.amount = 1_100 }
        #expect(CurrencyLock.scheduledAccountIDs(in: repository.snapshot) == [Fix.savingsID, Self.walletID])
    }

    @Test("A deleted occurrence record, and a value its edit's fields don't set, lock nothing")
    func deletedAndUnsetValuesDoNotLock() {
        var item = Fix.rent(start: Fix.day(2026, 8, 5), automatic: false)
        item.occurrences = [
            ScheduledOccurrence(
                id: UUID(),
                day: Self.november,
                outcome: .edited,
                edit: ScheduledOccurrenceEdit(fields: [.account], accountID: Self.cardID),
                createdAt: Fix.created,
                deletedAt: Fix.created,
            ),
            ScheduledOccurrence(
                id: UUID(),
                day: Self.december,
                outcome: .edited,
                edit: ScheduledOccurrenceEdit(
                    fields: [.amount],
                    amount: 1_100,
                    accountID: Self.walletID,
                    transferAccountID: Self.yenID,
                ),
                createdAt: Fix.created,
            ),
        ]
        #expect(CurrencyLock.scheduledAccountIDs([item]) == Set(item.accountIDs))
    }

    @Test("A deleted item locks neither its own accounts nor its occurrences' own (Tech Architect n1 on #202)")
    func deletedItemLocksNothing() throws {
        let repository = try scene(transfer: true)
        try edit(Self.december, repository, .thisOccurrence, toYen)
        #expect(CurrencyLock.scheduledAccountIDs(in: repository.snapshot).isSuperset(of: [Self.walletID, Self.yenID]))
        repository.snapshot.scheduledItems[0].deletedAt = Fix.date(2026, 10, 21)
        #expect(CurrencyLock.scheduledAccountIDs(in: repository.snapshot).isEmpty)
        try moveToEuro(Self.walletID, in: repository)
        try moveToEuro(Self.yenID, in: repository)
    }

    @Test("B2's drop leaves a paid occurrence's own $13 alone when All future moves To; Undo both and it's payable")
    func paidOccurrenceKeepsItsReceived() throws {
        let repository = try scene(transfer: true)
        try edit(Self.november, repository) { $0.destinationAmount = 13 }
        repository.now = Fix.date(2026, 11, 6)
        let item = try stored(repository)
        let paid = try #require(
            try repository.useCases().pay(itemID: item.id, occurrence: Self.november, on: Self.november, custom: nil)
        )
        #expect(paid.transaction?.destinationAmount == 13)
        let current = try stored(repository)
        var form = current.resolved(for: Self.december)
        form.occurrences = current.occurrences
        toYen(&form)
        let save = ScheduledOccurrenceSave(occurrence: Self.december, dueDay: Self.december, scope: .allFuture)
        let change = try repository.useCases().update(form, editing: save, payee: nil)
        let record = try #require(try stored(repository).occurrence(on: Self.november))
        #expect(record.outcome.isSettled)
        #expect(record.edit?.destinationAmount == 13 && record.edit?.receivedCurrencyCode == "USD")
        // Undo goes newest first: the save, then the Pay, which gives 5 Nov back open with its own $13.
        _ = try repository.revertScheduledItemSave(change, undone: false)
        guard case .reverted = try repository.unsettleScheduledOccurrence(paid) else {
            Issue.record("Undo Pay didn't revert")
            return
        }
        let reopened = try stored(repository)
        #expect(!reopened.isSettled(Self.november))
        #expect(reopened.resolved(for: Self.november).destinationAmount == 13)
        #expect(
            LedgerBook.receivedCurrencyIsCurrent(of: reopened.resolved(for: Self.november), in: repository.snapshot)
        )
        #expect(repository.snapshot.transactions.isEmpty)
    }
}

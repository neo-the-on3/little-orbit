import Foundation
import LittleOrbitDomain
import Testing

/// #207 t2: a catch-up posting refused with `receivedCurrencyMismatch` leaves the ledger as it was. Catch-up is
/// atomic per item: a failing item writes no transaction and no occurrence record, for any of its due days, and
/// keeps its next due day; the other automatic items still post in the same run (#26). Here To's currency moved
/// from USD to EUR after Rent Share was saved, written straight into the ledger as data from before the currency
/// lock (D410.1) can hold it. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("A failed catch-up posting leaves the ledger unchanged (#207 t2)")
struct ScheduledCatchUpRollbackTests {
    private typealias Fix = ScheduledFixture
    private static let cardID = UUID(uuidString: "5C000000-0000-4000-8000-000000000030")!
    private static let today = Fix.day(2026, 10, 20)

    /// ₹1,000 a month from Everyday Savings to Travel Card from 5 Aug, received $12; automatic.
    private static let share = ScheduledItem(
        type: .transfer,
        amount: 1_000,
        destinationAmount: 12,
        receivedCurrencyCode: "USD",
        accountID: Fix.savingsID,
        transferAccountID: cardID,
        details: "Rent Share",
        startDay: Fix.day(2026, 8, 5),
        processesAutomatically: true,
        timeZoneID: Fix.zone,
        createdAt: Fix.created,
    )

    /// Rent Share saved (and, with `rent`, Rent too), then Travel Card moved to EUR behind the lock's back.
    private func staleRepository(withRent rent: ScheduledItem? = nil) throws -> FakeScheduleRepository {
        var ledger = Fix.ledger
        ledger.accounts.append(
            Account(id: Self.cardID, name: "Travel Card", type: .cash, currencyCode: "USD", createdAt: Fix.created)
        )
        let repository = FakeScheduleRepository(ledger)
        repository.now = Fix.created
        try repository.useCases().save(Self.share)
        if let rent {
            try repository.useCases().save(rent)
        }
        let index = try #require(repository.snapshot.accounts.firstIndex { $0.id == Self.cardID })
        repository.snapshot.accounts[index].currencyCode = "EUR"
        repository.now = Fix.date(2026, 10, 20)
        return repository
    }

    private func item(_ id: UUID, in snapshot: LedgerSnapshot) throws -> ScheduledItem {
        try #require(snapshot.scheduledItems.first { $0.id == id })
    }

    @Test("Only the stale item due: nothing posts, and the whole ledger is exactly as it was")
    func onlyStaleItem() throws {
        let repository = try staleRepository()
        let before = repository.snapshot
        #expect(ScheduleCalendar.dueDays(of: Self.share, through: Self.today).count == 3)
        let result = try repository.useCases().catchUp(atLaunch: true)
        #expect(result.failedItemIDs == [Self.share.id])
        #expect(result.posted.isEmpty)
        #expect(repository.snapshot == before)
        #expect(repository.posted(for: Self.share.id).isEmpty)
        #expect(try LedgerBook.balance(of: Fix.savingsID, in: repository.snapshot) == 100_000)
        #expect(try LedgerBook.balance(of: Self.cardID, in: repository.snapshot) == 0)
    }

    @Test("Another due item still posts; the stale one keeps no transaction, no record and its next due day")
    func otherItemsStillPost() throws {
        let rent = Fix.rent(amount: 25_000, start: Fix.day(2026, 8, 1))
        let repository = try staleRepository(withRent: rent)
        let before = repository.snapshot
        let shareBefore = try item(Self.share.id, in: before)
        let result = try repository.useCases().catchUp(atLaunch: true)
        #expect(result.failedItemIDs == [Self.share.id])
        #expect(result.posted.count == 3)
        #expect(result.posted.allSatisfy { $0.scheduledTemplateID == rent.id })
        // The stale item: unchanged, field for field, with its first unpaid day still next.
        let shareAfter = try item(Self.share.id, in: repository.snapshot)
        #expect(shareAfter == shareBefore)
        #expect(shareAfter.occurrences.isEmpty)
        #expect(
            ScheduleCalendar.dueDays(of: shareAfter, through: Self.today)
                == ScheduleCalendar.dueDays(of: shareBefore, through: Self.today)
        )
        #expect(ScheduleCalendar.dueDays(of: shareAfter, through: Self.today).first == Fix.day(2026, 8, 5))
        #expect(repository.posted(for: Self.share.id).isEmpty)
        // Only Rent's three postings changed the balances; Travel Card got nothing.
        #expect(try LedgerBook.balance(of: Fix.savingsID, in: repository.snapshot) == 25_000)
        #expect(try LedgerBook.balance(of: Self.cardID, in: repository.snapshot) == 0)
        #expect(repository.snapshot.transactions.count == before.transactions.count + 3)
        #expect(try item(rent.id, in: repository.snapshot).occurrences.count == 3)
    }

    @Test("A due day recorded before the failing one isn't kept: the item's days roll back together")
    func noPartialWritesWithinTheItem() throws {
        let repository = try staleRepository()
        // 5 Aug's transaction is in the ledger without its record (an edited backup), so catch-up would only record
        // that day, which needs no posting, before 5 Sep's posting is refused.
        let first = try LedgerBook.scheduledTransaction(
            for: Self.share,
            occurrence: Fix.day(2026, 8, 5),
            postedOn: Fix.day(2026, 8, 5),
            now: Fix.created,
        )
        repository.snapshot.transactions.append(first)
        let before = repository.snapshot
        let result = try repository.useCases().catchUp(atLaunch: true)
        #expect(result.failedItemIDs == [Self.share.id])
        #expect(result.posted.isEmpty)
        #expect(try item(Self.share.id, in: repository.snapshot).occurrences.isEmpty, "5 Aug's record rolled back")
        #expect(repository.snapshot == before)
    }
}

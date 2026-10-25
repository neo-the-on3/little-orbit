import Foundation
import LittleOrbitDomain
import Testing

/// Pay with a custom date or amount (#26, D24): only this occurrence changes; the schedule, its amount and its anchor
/// day stay as they are.
@MainActor
@Suite("Scheduled custom pay (#26, D24)")
struct ScheduledCustomPayTests {
    private typealias Fix = ScheduledFixture

    private func repository(with item: ScheduledItem, today: Date) throws -> FakeScheduleRepository {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        try repository.useCases().save(item)
        repository.now = today
        return repository
    }

    private func custom(
        _ amount: Decimal,
        account: UUID = Fix.savingsID,
        category: UUID? = Fix.housingID,
        future: Bool = false,
    ) -> ScheduledCustomPayment {
        ScheduledCustomPayment(
            amount: amount,
            accountID: account,
            categoryID: category,
            changesFutureOccurrences: future,
        )
    }

    /// The item's first unsettled occurrence on or after `day`.
    private func next(_ item: ScheduledItem, in repository: FakeScheduleRepository, from day: CalendarDay)
        throws -> CalendarDay?
    {
        let stored = try #require(repository.snapshot.scheduledItems.first { $0.id == item.id })
        return ScheduleCalendar.firstOccurrence(of: stored, onOrAfter: day, where: { !stored.isSettled($0) })
    }

    @Test("S21: ₹27,500 on 3 Nov for the 1 Nov rent records that, and the item still shows ₹25,000, next 1 Dec")
    func customDateAndAmount() throws {
        let rent = Fix.rent(start: Fix.day(2026, 11, 1), automatic: false)
        let repository = try repository(with: rent, today: Fix.date(2026, 11, 3))
        let change = try #require(
            try repository.useCases()
                .pay(
                    itemID: rent.id,
                    occurrence: Fix.day(2026, 11, 1),
                    on: Fix.day(2026, 11, 3),
                    custom: custom(27_500),
                )
        )
        let transaction = try #require(change.transaction)
        #expect(transaction.amount == 27_500)
        #expect(TransactionTiming.day(of: transaction) == Fix.day(2026, 11, 3))
        #expect(transaction.id == ScheduledKey.transactionID(item: rent.id, day: Fix.day(2026, 11, 1)))
        let stored = try #require(repository.snapshot.scheduledItems.first)
        #expect(stored.amount == 25_000)
        #expect(stored.startDay == Fix.day(2026, 11, 1))
        #expect(try next(rent, in: repository, from: Fix.day(2026, 11, 1)) == Fix.day(2026, 12, 1))
        #expect(try repository.useCases().listing().board.overdue.isEmpty)
    }

    @Test("S47: a 31st-anchored item paid for February on 25 Feb is next due 31 Mar, not 25 Mar")
    func customDateKeepsTheAnchor() throws {
        let card = Fix.rent(amount: 4_000, start: Fix.day(2027, 1, 31), automatic: false)
        let repository = try repository(with: card, today: Fix.date(2027, 2, 25))
        try repository.useCases()
            .pay(itemID: card.id, occurrence: Fix.day(2027, 2, 28), on: Fix.day(2027, 2, 25), custom: nil)
        #expect(repository.posted(for: card.id).map(\.amount) == [4_000])
        #expect(try next(card, in: repository, from: Fix.day(2027, 2, 28)) == Fix.day(2027, 3, 31))
    }

    @Test("A custom payment twice on the same occurrence records it once")
    func customPayOnce() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try repository(with: rent, today: Fix.date(2026, 10, 20))
        let useCases = repository.useCases()
        let first = try useCases.pay(
            itemID: rent.id,
            occurrence: Fix.day(2026, 8, 1),
            on: Fix.day(2026, 8, 3),
            custom: custom(1),
        )
        let second = try useCases.payNow(itemID: rent.id, occurrence: Fix.day(2026, 8, 1))
        #expect(first != nil)
        #expect(second == nil)
        #expect(repository.posted(for: rent.id).map(\.amount) == [1])
    }

    @Test("A custom amount of zero isn't recorded")
    func zeroAmount() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try repository(with: rent, today: Fix.date(2026, 10, 20))
        #expect(throws: LedgerValidationError.self) {
            try repository.useCases()
                .pay(itemID: rent.id, occurrence: Fix.day(2026, 8, 1), on: Fix.day(2026, 10, 20), custom: custom(0))
        }
        #expect(repository.posted(for: rent.id).isEmpty)
        #expect(repository.snapshot.scheduledItems.first?.occurrences.isEmpty == true)
    }

    @Test("A custom payment from another account and category records them for this payment only")
    func customAccountAndCategory() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try repository(with: rent, today: Fix.date(2026, 10, 20))
        let change = try #require(
            try repository.useCases()
                .pay(
                    itemID: rent.id,
                    occurrence: Fix.day(2026, 8, 1),
                    on: Fix.day(2026, 10, 20),
                    custom: custom(25_000, account: Fix.fundID, category: nil),
                )
        )
        #expect(change.transaction?.accountID == Fix.fundID)
        #expect(change.transaction?.categoryID == nil)
        #expect(change.scheduleBefore == nil)
        let stored = try #require(repository.snapshot.scheduledItems.first)
        #expect(stored.accountID == Fix.savingsID)
        #expect(stored.categoryID == Fix.housingID)
    }

    @Test(
        "Also change future occurrences changes the schedule's amount, account and category from now on, never its dates; Undo restores it"
    )
    func changeFuturePayments() throws {
        let rent = Fix.rent(start: Fix.day(2026, 11, 1), automatic: false)
        let repository = try repository(with: rent, today: Fix.date(2026, 11, 3))
        let change = try #require(
            try repository.useCases()
                .pay(
                    itemID: rent.id,
                    occurrence: Fix.day(2026, 11, 1),
                    on: Fix.day(2026, 11, 3),
                    custom: custom(26_000, account: Fix.fundID, category: nil, future: true),
                )
        )
        var stored = try #require(repository.snapshot.scheduledItems.first)
        #expect(stored.amount == 26_000)
        #expect(stored.accountID == Fix.fundID)
        #expect(stored.categoryID == nil)
        #expect(stored.startDay == Fix.day(2026, 11, 1))
        #expect(stored.resumesOn == nil)
        #expect(change.scheduleBefore?.amount == 25_000)
        #expect(try next(rent, in: repository, from: Fix.day(2026, 11, 1)) == Fix.day(2026, 12, 1))
        // Undo puts the schedule back too (D288.3); Redo changes it again.
        guard case .reverted(let undone) = try repository.unsettleScheduledOccurrence(change) else {
            Issue.record("Expected the undo to revert")
            return
        }
        stored = try #require(repository.snapshot.scheduledItems.first)
        #expect(stored.amount == 25_000)
        #expect(stored.accountID == Fix.savingsID)
        #expect(stored.categoryID == Fix.housingID)
        #expect(repository.posted(for: rent.id).isEmpty)
        guard case .reverted = try repository.resettleScheduledOccurrence(undone) else {
            Issue.record("Expected the redo to revert")
            return
        }
        #expect(repository.snapshot.scheduledItems.first?.amount == 26_000)
        #expect(repository.posted(for: rent.id).map(\.amount) == [26_000])
    }
}

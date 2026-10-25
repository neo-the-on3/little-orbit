import Foundation
import LittleOrbitDomain
import Testing

/// S85, D136.3: scheduled occurrences after today show in the account's history as Upcoming rows with projected
/// balances; nothing is stored, and the current balance doesn't change.
@MainActor
@Suite("Scheduled occurrences in account history (S85)")
struct ScheduledProjectionTests {
    private typealias Fix = ScheduledFixture
    private let today = ScheduledFixture.day(2026, 10, 20)

    private func ledger(_ items: ScheduledItem...) throws -> LedgerSnapshot {
        var snapshot = Fix.ledger
        for item in items {
            snapshot = try LedgerBook.savingScheduledItem(
                item,
                in: snapshot,
                today: Fix.day(2026, 7, 1),
                now: Fix.created,
            )
        }
        return snapshot
    }

    @Test("A month ahead: weekly items project each occurrence after today, never today")
    func horizon() throws {
        let gym = Fix.rent(amount: 500, start: Fix.day(2026, 10, 20), rule: .every(1, .week), automatic: false)
        let snapshot = try ledger(gym)
        let days = ScheduledProjection.upcoming(on: Fix.savingsID, in: snapshot, today: today)
            .map { TransactionTiming.day(of: $0) }
        #expect(
            days == [Fix.day(2026, 10, 27), Fix.day(2026, 11, 3), Fix.day(2026, 11, 10), Fix.day(2026, 11, 17)]
        )
    }

    @Test("An item further away than the horizon still shows its next occurrence")
    func nextOccurrence() throws {
        let insurance = Fix.rent(amount: 12_000, start: Fix.day(2027, 3, 1), rule: .every(1, .year))
        let projected = ScheduledProjection.upcoming(on: Fix.savingsID, in: try ledger(insurance), today: today)
        #expect(projected.map { TransactionTiming.day(of: $0) } == [Fix.day(2027, 3, 1)])
        #expect(projected.first?.scheduledTemplateID == insurance.id)
        #expect(projected.first?.amount == 12_000)
    }

    @Test("A transfer projects on both of its accounts; another account's item doesn't")
    func accounts() throws {
        let transfer = Fix.transfer(start: Fix.day(2026, 11, 5), end: nil)
        let snapshot = try ledger(transfer)
        #expect(ScheduledProjection.upcoming(on: Fix.savingsID, in: snapshot, today: today).count == 1)
        #expect(ScheduledProjection.upcoming(on: Fix.fundID, in: snapshot, today: today).count == 1)
        #expect(ScheduledProjection.upcoming(on: UUID(), in: snapshot, today: today).isEmpty)
    }

    @Test("History: projected rows are Upcoming with running projected balances and their item; current balance stays")
    func history() throws {
        let rent = Fix.rent(start: Fix.day(2026, 11, 1), automatic: false)
        let snapshot = try ledger(rent)
        let account = try #require(snapshot.accounts.first { $0.id == Fix.savingsID })
        let entered = Transaction(
            type: .expense,
            amount: 1_000,
            date: Fix.date(2026, 10, 25),
            timeZoneID: Fix.zone,
            accountID: Fix.savingsID,
            createdAt: Fix.created,
        )
        let projected = ScheduledProjection.upcoming(on: Fix.savingsID, in: snapshot, today: today)
        let history = BuildAccountHistory()(
            account: account,
            transactions: [entered],
            today: today,
            projected: projected,
        )
        #expect(history.currentBalance == 100_000)
        #expect(history.upcoming.map(\.balanceAfter) == [74_000, 99_000])
        #expect(history.upcoming.map(\.scheduledItemID) == [rent.id, nil])
        #expect(history.balanceAfterUpcoming == 74_000)
    }

    @Test("A projected occurrence already stored, or due today, isn't shown again")
    func noDuplicates() throws {
        let rent = Fix.rent(start: Fix.day(2026, 10, 20), automatic: false)
        let snapshot = try ledger(rent)
        let account = try #require(snapshot.accounts.first { $0.id == Fix.savingsID })
        let november = try LedgerBook.scheduledTransaction(
            for: rent,
            occurrence: Fix.day(2026, 11, 20),
            postedOn: Fix.day(2026, 11, 20),
            now: Fix.created,
        )
        let history = BuildAccountHistory()(
            account: account,
            transactions: [november],
            today: today,
            projected: [november],
        )
        #expect(history.upcoming.count == 1)
        #expect(history.upcoming.first?.scheduledItemID == nil)
    }
}

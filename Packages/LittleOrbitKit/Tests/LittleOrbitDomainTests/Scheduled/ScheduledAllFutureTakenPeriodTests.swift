import Foundation
import LittleOrbitDomain
import Testing

/// D433.1 (Product Manager, with D432): an "All future occurrences" move into a period that already holds an
/// occurrence keeps the moved occurrence, as the user's own, so catch-up's taken-period check (D427, #316) never
/// drops it. Made-up data: Rent ₹25,000 from Everyday Savings, and a ₹1,200 bill every 3 months.
@MainActor
@Suite("An All future move into a taken period stays the user's own (D433.1)")
struct ScheduledAllFutureTakenPeriodTests {
    private typealias Fix = ScheduledFixture
    private let base = ScheduledOccurrenceEditTests()

    private func outcome(_ id: UUID, on day: CalendarDay, _ repository: FakeScheduleRepository) -> ScheduledOutcome? {
        repository.snapshot.scheduledItems.first { $0.id == id }?.occurrence(on: day)?.outcome
    }

    @Test("Monthly, 1 Oct paid, 1 Nov moved to 31 Oct for all future: 31 Oct is kept as pending, then 30 Nov")
    func monthlyIntoPaidMonth() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try base.scene(rent)
        for month in 8...10 {
            let day = Fix.day(2026, month, 1)
            _ = try repository.useCases().pay(itemID: rent.id, occurrence: day, on: day, custom: nil)
        }
        try base.edit(
            rent.id,
            in: repository,
            occurrence: Fix.day(2026, 11, 1),
            dueDay: Fix.day(2026, 10, 31),
            scope: .allFuture,
        )
        #expect(outcome(rent.id, on: Fix.day(2026, 10, 31), repository) == .pending)
        #expect(
            try base.next(rent.id, repository, count: 2).map(\.day) == [Fix.day(2026, 10, 31), Fix.day(2026, 11, 30)]
        )
    }

    @Test("Every 3 months, 15 Jan skipped, 15 Apr moved to 20 Mar for all future: 20 Mar is kept as pending")
    func quarterlyIntoSkippedPeriod() throws {
        let bill = Fix.rent(amount: 1_200, start: Fix.day(2027, 1, 15), rule: .every(3, .month), automatic: false)
        let repository = try base.scene(bill, today: Fix.day(2027, 3, 1))
        try repository.useCases().skip(itemID: bill.id, occurrence: Fix.day(2027, 1, 15))
        try base.edit(
            bill.id,
            in: repository,
            occurrence: Fix.day(2027, 4, 15),
            dueDay: Fix.day(2027, 3, 20),
            scope: .allFuture,
        )
        #expect(outcome(bill.id, on: Fix.day(2027, 3, 20), repository) == .pending)
        #expect(
            try base.next(bill.id, repository, count: 2).map(\.day) == [Fix.day(2027, 3, 20), Fix.day(2027, 6, 20)]
        )
    }

    @Test("A move into a period with no other occurrence stays on the rule, with no pending record")
    func freePeriodStaysOnTheRule() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try base.scene(rent)
        for month in 8...10 {
            let day = Fix.day(2026, month, 1)
            _ = try repository.useCases().pay(itemID: rent.id, occurrence: day, on: day, custom: nil)
        }
        try base.edit(
            rent.id,
            in: repository,
            occurrence: Fix.day(2026, 11, 1),
            dueDay: Fix.day(2026, 11, 5),
            scope: .allFuture,
        )
        #expect(outcome(rent.id, on: Fix.day(2026, 11, 5), repository) == nil)
        #expect(
            try base.next(rent.id, repository, count: 2).map(\.day) == [Fix.day(2026, 11, 5), Fix.day(2026, 12, 5)]
        )
    }
}

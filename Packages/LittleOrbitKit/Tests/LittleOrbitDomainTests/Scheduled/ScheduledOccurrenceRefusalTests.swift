import Foundation
import LittleOrbitDomain
import Testing

/// Occurrence edits that would lose an occurrence are refused, and nothing is written: moving the anchor onto a day
/// that already has an occurrence, or so that a later occurrence's new day has one (D381.1, #221), and "This
/// occurrence only" for an occurrence paid or skipped since the form opened (D381.2, #222). A SERIES change that
/// takes the occurrence off the rule still saves to the next one. Made-up data.
@MainActor
@Suite("Refused occurrence edits (D381.1, D381.2)")
struct ScheduledOccurrenceRefusalTests {
    private typealias Fix = ScheduledFixture

    private func scene(_ item: ScheduledItem) throws -> FakeScheduleRepository {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        try repository.useCases().save(item)
        repository.now = Fix.date(2026, 10, 20)
        return repository
    }

    private func stored(_ repository: FakeScheduleRepository) throws -> ScheduledItem {
        try #require(repository.snapshot.scheduledItems.first)
    }

    /// Saves `change` applied to `item` as the form opened on `key` showed it.
    private func edit(
        _ item: ScheduledItem,
        in repository: FakeScheduleRepository,
        occurrence key: CalendarDay,
        dueDay: CalendarDay? = nil,
        scope: ScheduledEditScope,
        _ change: (inout ScheduledItem) -> Void = { _ in },
    ) throws {
        var form = item.resolved(for: key)
        form.occurrences = item.occurrences
        change(&form)
        let save = ScheduledOccurrenceSave(occurrence: key, dueDay: dueDay ?? item.dueDay(of: key), scope: scope)
        _ = try repository.useCases().update(form, editing: save, payee: nil)
    }

    @Test("D381.1: All future occurrences from 1 Oct moved onto 1 Sep, still overdue, is refused")
    func anchorOntoEarlierOpenDay() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent)
        let before = repository.snapshot
        let september = Fix.day(2026, 9, 1)
        #expect(throws: LedgerValidationError.occurrenceDayTaken(september)) {
            try edit(
                try stored(repository),
                in: repository,
                occurrence: Fix.day(2026, 10, 1),
                dueDay: september,
                scope: .allFuture,
            )
        }
        #expect(repository.snapshot == before)
    }

    @Test("D381.1: All future occurrences moved onto a skipped day is refused")
    func anchorOntoSettledDay() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent)
        let november = Fix.day(2026, 11, 1)
        _ = try repository.useCases().skip(itemID: rent.id, occurrence: november)
        let before = repository.snapshot
        #expect(throws: LedgerValidationError.occurrenceDayTaken(november)) {
            try edit(
                try stored(repository),
                in: repository,
                occurrence: Fix.day(2026, 10, 1),
                dueDay: november,
                scope: .allFuture,
            )
        }
        #expect(repository.snapshot == before)
    }

    @Test("D381.1: a later occurrence with its own amount whose new day is skipped is refused, not dropped")
    func laterOccurrenceKeyTaken() throws {
        // Every 2 days from 21 Oct: 21, 23, 25, 27 Oct… 25 Oct has its own amount and 27 Oct is skipped.
        let item = Fix.rent(amount: 300, start: Fix.day(2026, 10, 21), rule: .every(2, .day), automatic: false)
        let repository = try scene(item)
        try edit(try stored(repository), in: repository, occurrence: Fix.day(2026, 10, 25), scope: .thisOccurrence) {
            $0.amount = 350
        }
        _ = try repository.useCases().skip(itemID: item.id, occurrence: Fix.day(2026, 10, 27))
        let before = repository.snapshot
        // From 23 Oct, 25 Oct (two after 21 Oct) would move to 27 Oct, which is skipped.
        #expect(throws: LedgerValidationError.occurrenceDayTaken(Fix.day(2026, 10, 27))) {
            try edit(
                try stored(repository),
                in: repository,
                occurrence: Fix.day(2026, 10, 21),
                dueDay: Fix.day(2026, 10, 23),
                scope: .allFuture,
            )
        }
        #expect(repository.snapshot == before)
        #expect(try stored(repository).resolved(for: Fix.day(2026, 10, 25)).amount == 350)
    }

    @Test("D106 still: All future occurrences onto a free day moves the anchor")
    func anchorOntoFreeDay() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent)
        try edit(
            try stored(repository),
            in: repository,
            occurrence: Fix.day(2026, 10, 1),
            dueDay: Fix.day(2026, 10, 5),
            scope: .allFuture,
        )
        #expect(try stored(repository).startDay == Fix.day(2026, 10, 5))
    }

    @Test("D381.2: This occurrence only for an occurrence skipped since the form opened is refused")
    func staleThisOccurrence() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent)
        let october = Fix.day(2026, 10, 1)
        let opened = try stored(repository)
        _ = try repository.useCases().skip(itemID: rent.id, occurrence: october)
        let before = repository.snapshot
        #expect(throws: LedgerValidationError.occurrenceSettledSinceOpened) {
            try edit(opened, in: repository, occurrence: october, scope: .thisOccurrence) { $0.amount = 26_000 }
        }
        #expect(repository.snapshot == before)
        #expect(try stored(repository).resolved(for: Fix.day(2026, 11, 1)).amount == 25_000)
    }

    @Test("D346.2 still: a new start that takes the occurrence off the rule saves to the next one")
    func seriesRetargetStays() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent)
        let november = Fix.day(2026, 11, 1)
        try edit(try stored(repository), in: repository, occurrence: november, scope: .thisOccurrence) {
            $0.startDay = Fix.day(2026, 8, 3)
            $0.amount = 26_000
        }
        let item = try stored(repository)
        #expect(item.startDay == Fix.day(2026, 8, 3))
        #expect(item.resolved(for: Fix.day(2026, 11, 3)).amount == 26_000)
        #expect(item.amount == 25_000)
    }
}

import Foundation
import LittleOrbitDomain
import Testing

/// An automatic occurrence whose Pay was undone waits for the user (D344), and occurrence edits keep that: moving the
/// anchor carries the mark to the moved occurrence (D344.1), and Undo Pay of an occurrence with its own values puts
/// them back with it (#201 with #202). Made-up data.
@MainActor
@Suite("Occurrence edits and an undone automatic Pay (D344.1)")
struct ScheduledOccurrenceWaitingTests {
    private typealias Fix = ScheduledFixture
    private static let august = Fix.day(2026, 8, 1)

    /// Automatic Rent, monthly on the 1st from 1 Aug, opened on 20 Oct before any catch-up.
    private func scene() throws -> (FakeScheduleRepository, ScheduledItem) {
        let rent = Fix.rent(automatic: true)
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        try repository.useCases().save(rent)
        repository.now = Fix.date(2026, 10, 20)
        return (repository, rent)
    }

    private func stored(_ repository: FakeScheduleRepository) throws -> ScheduledItem {
        try #require(repository.snapshot.scheduledItems.first)
    }

    private func payAndUndo(_ rent: ScheduledItem, in repository: FakeScheduleRepository) throws -> Transaction? {
        let today = Fix.day(2026, 10, 20)
        let paid = try #require(
            try repository.useCases().pay(itemID: rent.id, occurrence: Self.august, on: today, custom: nil)
        )
        guard case .reverted = try repository.unsettleScheduledOccurrence(paid) else {
            Issue.record("Expected the undo to revert")
            return nil
        }
        return paid.transaction
    }

    private func edit(
        in repository: FakeScheduleRepository,
        dueDay: CalendarDay? = nil,
        scope: ScheduledEditScope,
        _ change: (inout ScheduledItem) -> Void = { _ in },
    ) throws {
        let current = try stored(repository)
        var item = current.resolved(for: Self.august)
        item.occurrences = current.occurrences
        change(&item)
        let day = dueDay ?? current.dueDay(of: Self.august)
        let save = ScheduledOccurrenceSave(occurrence: Self.august, dueDay: day, scope: scope)
        _ = try repository.useCases().update(item, editing: save, payee: nil)
    }

    @Test("D344.1: All future occurrences with a new due day keeps the waiting mark; catch-up never records it")
    func moveAnchorKeepsWaiting() throws {
        let (repository, rent) = try scene()
        let undone = try #require(try payAndUndo(rent, in: repository))
        let moved = Fix.day(2026, 8, 5)
        try edit(in: repository, dueDay: moved, scope: .allFuture)
        let record = try #require(try stored(repository).occurrence(on: moved))
        #expect(record.outcome == .pending)
        #expect(record.transactionID == undone.id)
        #expect(record.waitsForUser)
        // Catch-up records 5 Sep and 5 Oct, as the new rule says, and leaves 5 Aug to the user.
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.count == 2)
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
        #expect(try stored(repository).occurrence(on: moved)?.waitsForUser == true)
        let board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [moved])
        #expect(board.overdue.first?.waitsForUser == true)
    }

    @Test("D344.1: This occurrence only with a new due day keeps the waiting mark, and the row says so by its key")
    func moveOneKeepsWaiting() throws {
        let (repository, rent) = try scene()
        let undone = try #require(try payAndUndo(rent, in: repository))
        let moved = Fix.day(2026, 8, 5)
        try edit(in: repository, dueDay: moved, scope: .thisOccurrence)
        let record = try #require(try stored(repository).occurrence(on: Self.august))
        #expect(record.transactionID == undone.id)
        #expect(record.waitsForUser)
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.count == 2)
        let board = try repository.useCases().listing().board
        let row = try #require(board.overdue.first { $0.key == Self.august })
        #expect(row.day == moved)
        #expect(row.waitsForUser)
    }

    @Test("Undo Pay of an automatic occurrence with its own values puts them back with the waiting mark")
    func undoKeepsOwnValues() throws {
        let (repository, rent) = try scene()
        let moved = Fix.day(2026, 8, 3)
        try edit(in: repository, dueDay: moved, scope: .thisOccurrence) { $0.amount = 26_000 }
        _ = try payAndUndo(rent, in: repository)
        let item = try stored(repository)
        #expect(item.occurrence(on: Self.august)?.waitsForUser == true)
        #expect(item.resolved(for: Self.august).amount == 26_000)
        #expect(item.dueDay(of: Self.august) == moved)
    }
}

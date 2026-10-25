import Foundation
import LittleOrbitDomain
import Testing

/// Undo and Redo of a manual Pay or Skip (D288.3): Undo Pay removes the transaction and puts the occurrence back;
/// Redo records it again, once; a step whose item or transaction changed since is stale and writes nothing.
@MainActor
@Suite("Scheduled Pay and Skip undo (D288.3)")
struct ScheduledUndoTests {
    private typealias Fix = ScheduledFixture
    private static let august = Fix.day(2026, 8, 1)

    /// Manual Rent, monthly on the 1st from 1 Aug, with Aug, Sep and Oct overdue on 20 Oct.
    private func scene() throws -> (FakeScheduleRepository, ScheduledItem) {
        let rent = Fix.rent(automatic: false)
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        try repository.useCases().save(rent)
        repository.now = Fix.date(2026, 10, 20)
        return (repository, rent)
    }

    private func undo(_ change: ScheduledSettlementChange, in repository: FakeScheduleRepository) throws
        -> ScheduledSettlementChange
    {
        let result = try repository.unsettleScheduledOccurrence(change)
        guard case .reverted(let left) = result else {
            Issue.record("Expected the undo to revert, got \(result)")
            return change
        }
        return left
    }

    @Test("S89: Undo Pay removes the transaction and puts the occurrence and the badge back")
    func undoPay() throws {
        let (repository, rent) = try scene()
        let useCases = repository.useCases()
        let paid = try #require(
            try useCases.pay(itemID: rent.id, occurrence: Self.august, on: Fix.day(2026, 10, 20), custom: nil)
        )
        #expect(try useCases.listing().board.overdueCount == 2)
        _ = try undo(paid, in: repository)
        #expect(repository.posted(for: rent.id).isEmpty)
        #expect(repository.snapshot.scheduledItems.first?.occurrences.isEmpty == true)
        let board = try useCases.listing().board
        #expect(board.overdueCount == 3)
        #expect(board.overdue.first?.day == Self.august)
    }

    @Test("S89: Redo Pay records it again, once, with the same transaction ID")
    func redoPay() throws {
        let (repository, rent) = try scene()
        let useCases = repository.useCases()
        let paid = try #require(try useCases.payNow(itemID: rent.id, occurrence: Self.august))
        let change = try #require(
            repository.snapshot.scheduledItems.first.flatMap { item in
                item.occurrence(on: Self.august)
                    .map { ScheduledSettlementChange(item: item, record: $0, transaction: paid) }
            }
        )
        let undone = try undo(change, in: repository)
        let redo = try repository.resettleScheduledOccurrence(undone)
        guard case .reverted(let redone) = redo else {
            Issue.record("Expected the redo to revert, got \(redo)")
            return
        }
        #expect(repository.posted(for: rent.id).map(\.id) == [paid.id])
        #expect(redone.transaction?.id == paid.id)
        #expect(try useCases.listing().board.overdueCount == 2)
        // Exactly once: paying it again, or a catch-up, records nothing more.
        #expect(try useCases.payNow(itemID: rent.id, occurrence: Self.august) == nil)
        _ = try useCases.catchUp(atLaunch: true)
        #expect(repository.posted(for: rent.id).count == 1)
        // And it undoes again.
        _ = try undo(redone, in: repository)
        #expect(repository.posted(for: rent.id).isEmpty)
    }

    @Test("Undoing a manual Pay never lets catch-up record that occurrence")
    func undoneManualPayStaysUnrecorded() throws {
        let (repository, rent) = try scene()
        let useCases = repository.useCases()
        let paid = try #require(
            try useCases.pay(itemID: rent.id, occurrence: Self.august, on: Fix.day(2026, 10, 20), custom: nil)
        )
        _ = try undo(paid, in: repository)
        let result = try useCases.catchUp(atLaunch: true)
        #expect(result.posted.isEmpty)
        #expect(repository.posted(for: rent.id).isEmpty)
        #expect(try useCases.listing().board.overdueCount == 3)
    }

    @Test("S90: Undo Skip brings the occurrence back as it was; Redo skips it again")
    func undoSkip() throws {
        let (repository, rent) = try scene()
        let useCases = repository.useCases()
        let skipped = try #require(try useCases.skip(itemID: rent.id, occurrence: Self.august))
        #expect(skipped.transaction == nil)
        let undone = try undo(skipped, in: repository)
        #expect(try useCases.listing().board.overdueCount == 3)
        let redo = try repository.resettleScheduledOccurrence(undone)
        guard case .reverted = redo else {
            Issue.record("Expected the redo to revert, got \(redo)")
            return
        }
        #expect(repository.snapshot.scheduledItems.first?.occurrence(on: Self.august)?.outcome == .skipped)
        #expect(repository.posted(for: rent.id).isEmpty)
    }

    @Test("D336.1: undoing the payment of a kept day puts the pending record back")
    func undoKeptDay() throws {
        let (repository, rent) = try scene()
        var edited = try #require(repository.snapshot.scheduledItems.first)
        edited.startDay = Fix.day(2026, 8, 5)
        try repository.useCases().save(edited)
        let pending = try #require(repository.snapshot.scheduledItems.first?.occurrence(on: Self.august))
        #expect(pending.outcome == .pending)
        let paid = try #require(
            try repository.useCases()
                .pay(itemID: rent.id, occurrence: Self.august, on: Fix.day(2026, 10, 20), custom: nil)
        )
        #expect(paid.replaced == pending)
        _ = try undo(paid, in: repository)
        #expect(repository.snapshot.scheduledItems.first?.occurrence(on: Self.august) == pending)
        #expect(try repository.useCases().listing().board.overdue.map(\.day).contains(Self.august))
    }

    @Test("S91: Undo Pay after the transaction was edited is stale and changes nothing")
    func staleAfterTransactionEdit() throws {
        let (repository, rent) = try scene()
        let paid = try #require(
            try repository.useCases()
                .pay(itemID: rent.id, occurrence: Self.august, on: Fix.day(2026, 10, 20), custom: nil)
        )
        var edited = try #require(paid.transaction)
        edited.amount = 26_000
        repository.snapshot = try LedgerBook.savingTransaction(edited, in: repository.snapshot, now: repository.now)
        let before = repository.snapshot
        #expect(try repository.unsettleScheduledOccurrence(paid) == .stale(.changed([edited.id])))
        #expect(repository.snapshot == before)
    }

    @Test("Undo Pay after the transaction was deleted is stale")
    func staleAfterTransactionDelete() throws {
        let (repository, rent) = try scene()
        let paid = try #require(
            try repository.useCases()
                .pay(itemID: rent.id, occurrence: Self.august, on: Fix.day(2026, 10, 20), custom: nil)
        )
        let id = try #require(paid.transaction?.id)
        repository.snapshot = try LedgerBook.deletingTransaction(id: id, in: repository.snapshot, now: repository.now)
        #expect(try repository.unsettleScheduledOccurrence(paid) == .stale(.deleted([id])))
        // The occurrence stays settled: deleting its transaction never makes it due again.
        #expect(repository.snapshot.scheduledItems.first?.isSettled(Self.august) == true)
    }

    @Test("Undo Pay or Skip after the item was edited, or deleted, is stale")
    func staleAfterItemChange() throws {
        let (repository, rent) = try scene()
        let skipped = try #require(try repository.useCases().skip(itemID: rent.id, occurrence: Self.august))
        var edited = try #require(repository.snapshot.scheduledItems.first)
        edited.amount = 26_000
        try repository.useCases().save(edited)
        #expect(try repository.unsettleScheduledOccurrence(skipped) == .stale(.scheduledItemChanged(rent.id)))
        try repository.useCases().delete(id: rent.id)
        #expect(try repository.unsettleScheduledOccurrence(skipped) == .stale(.scheduledItemDeleted(rent.id)))
    }

    @Test("Undo Pay after the item's account was deleted is stale")
    func staleAfterAccountDelete() throws {
        let (repository, rent) = try scene()
        let paid = try #require(
            try repository.useCases()
                .pay(itemID: rent.id, occurrence: Self.august, on: Fix.day(2026, 10, 20), custom: nil)
        )
        repository.snapshot = try LedgerBook.deletingAccount(
            id: Fix.savingsID,
            in: repository.snapshot,
            now: repository.now,
        )
        #expect(try repository.unsettleScheduledOccurrence(paid) == .stale(.accountDeleted([Fix.savingsID])))
    }

    @Test("Paying another occurrence of the same item doesn't make an earlier step stale")
    func otherOccurrencesDontMatter() throws {
        let (repository, rent) = try scene()
        let useCases = repository.useCases()
        let paid = try #require(
            try useCases.pay(itemID: rent.id, occurrence: Self.august, on: Fix.day(2026, 10, 20), custom: nil)
        )
        try useCases.skip(itemID: rent.id, occurrence: Fix.day(2026, 9, 1))
        _ = try undo(paid, in: repository)
        #expect(repository.snapshot.scheduledItems.first?.occurrence(on: Fix.day(2026, 9, 1))?.outcome == .skipped)
    }

    @Test("Redo after the occurrence was paid again elsewhere is stale and records nothing more")
    func staleRedo() throws {
        let (repository, rent) = try scene()
        let useCases = repository.useCases()
        let paid = try #require(
            try useCases.pay(itemID: rent.id, occurrence: Self.august, on: Fix.day(2026, 10, 20), custom: nil)
        )
        let undone = try undo(paid, in: repository)
        try useCases.payNow(itemID: rent.id, occurrence: Self.august)
        #expect(try repository.resettleScheduledOccurrence(undone) == .stale(.scheduledItemChanged(rent.id)))
        #expect(repository.posted(for: rent.id).count == 1)
    }
}

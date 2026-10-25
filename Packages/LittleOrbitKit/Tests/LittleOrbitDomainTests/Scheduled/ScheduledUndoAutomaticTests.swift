import Foundation
import LittleOrbitDomain
import Testing

/// D344 (1): undoing the Pay of an automatic item's occurrence makes it due again and waits for the user. Catch-up
/// never records it, after any number of relaunches, until the user pays or skips it; Redo records it again as
/// usual, and later occurrences stay automatic. Tech Architect B1: Undo and Redo check every account they'd write.
@MainActor
@Suite("Scheduled Undo of an automatic Pay (D344) and the accounts a revert writes (B1)")
struct ScheduledUndoAutomaticTests {
    private typealias Fix = ScheduledFixture
    private static let august = Fix.day(2026, 8, 1)

    /// Automatic Rent, monthly on the 1st from 1 Aug, opened on 20 Oct before any catch-up.
    private func scene(automatic: Bool = true) throws -> (FakeScheduleRepository, ScheduledItem) {
        let rent = Fix.rent(automatic: automatic)
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

    private func pay(
        _ rent: ScheduledItem,
        _ day: CalendarDay = august,
        in repository: FakeScheduleRepository,
        custom: ScheduledCustomPayment? = nil,
    ) throws -> ScheduledSettlementChange {
        try #require(
            try repository.useCases().pay(itemID: rent.id, occurrence: day, on: Fix.day(2026, 10, 20), custom: custom)
        )
    }

    @Test("D344: Undo Pay leaves the occurrence due, never recorded by catch-up, across relaunches")
    func undoneStaysDue() throws {
        let (repository, rent) = try scene()
        let paid = try pay(rent, in: repository)
        _ = try undo(paid, in: repository)
        let record = try #require(repository.snapshot.scheduledItems.first?.occurrence(on: Self.august))
        #expect(record.outcome == .pending)
        #expect(record.outcome != .skipped)
        #expect(record.transactionID == paid.transaction?.id)
        #expect(record.waitsForUser)
        #expect(repository.posted(for: rent.id).isEmpty)

        // Launch: Sep and Oct are recorded for the user; Aug waits under Overdue like a manual item.
        let launch = try repository.useCases().catchUp(atLaunch: true)
        #expect(launch.posted.compactMap(\.scheduledOccurrenceDate).count == 2)
        #expect(repository.posted(for: rent.id).count == 2)
        var board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [Self.august])
        #expect(board.overdue.first?.waitsForUser == true)
        #expect(board.overdueCount == 1)

        // Relaunched on 2 Nov: 1 Nov is recorded, Aug still isn't (later occurrences stay automatic).
        repository.now = Fix.date(2026, 11, 2)
        let relaunch = try repository.useCases().catchUp(atLaunch: true)
        #expect(relaunch.posted.count == 1)
        #expect(!repository.posted(for: rent.id).contains { $0.id == paid.transaction?.id })
        board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [Self.august])
        #expect(board.overdueCount == 1)
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
    }

    @Test("D344: after the undo, Pay records it once and Skip settles it; either way catch-up stays out")
    func payOrSkipAfterUndo() throws {
        let (repository, rent) = try scene()
        _ = try undo(try pay(rent, in: repository), in: repository)
        _ = try repository.useCases().catchUp(atLaunch: true)
        let paid = try pay(rent, in: repository)
        #expect(paid.replaced?.waitsForUser == true)
        #expect(repository.posted(for: rent.id).count == 3)
        #expect(try repository.useCases().listing().board.overdueCount == 0)
        // Undone again, it waits again.
        _ = try undo(paid, in: repository)
        #expect(repository.snapshot.scheduledItems.first?.occurrence(on: Self.august)?.waitsForUser == true)
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)

        let skipped = try #require(try repository.useCases().skip(itemID: rent.id, occurrence: Self.august))
        #expect(skipped.transaction == nil)
        #expect(repository.snapshot.scheduledItems.first?.occurrence(on: Self.august)?.outcome == .skipped)
        #expect(repository.posted(for: rent.id).count == 2)
        #expect(try repository.useCases().listing().board.overdueCount == 0)
        // Undo Skip brings back the waiting record, not an automatic one.
        _ = try undo(skipped, in: repository)
        #expect(repository.snapshot.scheduledItems.first?.occurrence(on: Self.august)?.waitsForUser == true)
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
    }

    @Test("D344: Redo Pay records it again as usual, with the same transaction ID; Undo then waits again")
    func redo() throws {
        let (repository, rent) = try scene()
        let paid = try pay(rent, in: repository)
        let undone = try undo(paid, in: repository)
        let redo = try repository.resettleScheduledOccurrence(undone)
        guard case .reverted(let redone) = redo else {
            Issue.record("Expected the redo to revert, got \(redo)")
            return
        }
        let id = try #require(paid.transaction?.id)
        #expect(repository.posted(for: rent.id).map(\.id) == [id])
        #expect(repository.snapshot.scheduledItems.first?.occurrence(on: Self.august)?.outcome == .posted)
        _ = try repository.useCases().catchUp(atLaunch: true)
        #expect(repository.posted(for: rent.id).count == 3)
        _ = try undo(redone, in: repository)
        #expect(repository.snapshot.scheduledItems.first?.occurrence(on: Self.august)?.waitsForUser == true)
    }

    @Test("D344: a manual item's Undo Pay is unchanged: no record, nothing waits")
    func manualUnchanged() throws {
        let (repository, rent) = try scene(automatic: false)
        _ = try undo(try pay(rent, in: repository), in: repository)
        #expect(repository.snapshot.scheduledItems.first?.occurrences.isEmpty == true)
    }

    @Test("D344: the mark is a pending record with a transaction ID, in the existing fields; backups keep it")
    func markInExistingFields() throws {
        let (repository, rent) = try scene()
        _ = try undo(try pay(rent, in: repository), in: repository)
        let item = try #require(repository.snapshot.scheduledItems.first)
        let decoded = try JSONDecoder().decode(ScheduledItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
        #expect(decoded.occurrence(on: Self.august)?.waitsForUser == true)
        // A record without the mark writes no transaction ID, as before, so older backups stay byte-identical.
        let pending = ScheduledOccurrence(
            id: UUID(),
            day: Self.august,
            outcome: .pending,
            createdAt: Fix.created,
        )
        let json = try #require(String(data: try JSONEncoder().encode(pending), encoding: .utf8))
        #expect(!json.contains("transactionID"))
        #expect(!pending.waitsForUser)
    }

    @Test("B1 (a): Undo of a custom payment that changed the schedule is stale once its old account is deleted")
    func undoChecksTheScheduleBefore() throws {
        let (repository, rent) = try scene(automatic: false)
        let paid = try pay(
            rent,
            in: repository,
            custom: ScheduledCustomPayment(
                amount: 26_000,
                accountID: Fix.fundID,
                categoryID: Fix.housingID,
                changesFutureOccurrences: true,
            ),
        )
        #expect(repository.snapshot.scheduledItems.first?.accountID == Fix.fundID)
        repository.snapshot = try LedgerBook.deletingAccount(
            id: Fix.savingsID,
            in: repository.snapshot,
            now: repository.now,
        )
        let before = repository.snapshot
        #expect(try repository.unsettleScheduledOccurrence(paid) == .stale(.accountDeleted([Fix.savingsID])))
        #expect(repository.snapshot == before)
        #expect(repository.snapshot.scheduledItems.first?.accountID == Fix.fundID)
    }

    @Test("B1 (b): Redo of a custom payment is stale once its account is deleted, so it never fails every time")
    func redoChecksThePaymentAccount() throws {
        let (repository, rent) = try scene(automatic: false)
        let paid = try pay(
            rent,
            in: repository,
            custom: ScheduledCustomPayment(amount: 26_000, accountID: Fix.fundID, categoryID: Fix.housingID),
        )
        let undone = try undo(paid, in: repository)
        repository.snapshot = try LedgerBook.deletingAccount(
            id: Fix.fundID,
            in: repository.snapshot,
            now: repository.now,
        )
        let before = repository.snapshot
        #expect(try repository.resettleScheduledOccurrence(undone) == .stale(.accountDeleted([Fix.fundID])))
        #expect(repository.snapshot == before)
    }

    @Test("NB 2: Undo Pay is stale once a split, attachment or refund is linked to the payment")
    func linkedRecordsMakeUndoStale() throws {
        for link in 0..<3 {
            let (repository, rent) = try scene(automatic: false)
            let paid = try pay(rent, in: repository)
            let id = try #require(paid.transaction?.id)
            switch link {
            case 0:
                repository.snapshot.splits.append(TransactionSplit(transactionID: id))
            case 1:
                repository.snapshot.attachments.append(Attachment(transactionID: id))
            default:
                var refund = Transaction(type: .income, amount: 100, accountID: Fix.savingsID, isRefund: true)
                refund.refundOfID = id
                repository.snapshot.transactions.append(refund)
            }
            let before = repository.snapshot
            #expect(try repository.unsettleScheduledOccurrence(paid) == .stale(.changed([id])))
            #expect(repository.snapshot == before)
        }
    }
}

import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// A restore replaces the whole ledger, so no window may undo or redo a step made against the old data (D187.2,
/// Tech Architect N6): `LedgerUpdates.follow` clears every window's history from the backup service's signal.
@MainActor
@Suite("Restore and undo history")
struct BackupRestoreUndoTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @Test("A restore clears both windows' Undo and Redo, including a failed Undo still settling")
    func restoreClearsEveryWindow() async throws {
        let rows = (0..<3).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let repository = try F.repository(rows)
        let harness = try BackupHarness(repository: repository)
        let backup = try await harness.service.backUpNow()

        let disk = FullDiskLedgerRepository(repository)
        let updates = LedgerUpdates()
        updates.follow(harness.changes)
        let first = TestWindow(TransactionUseCases(repository: disk), updates: updates)
        let useCases = TransactionUseCases(repository: repository)
        let second = TestWindow(useCases, updates: updates)
        first.history.record(try TransactionUseCases(repository: disk).changes.remove(ids: [rows[0].id]))
        first.history.record(try TransactionUseCases(repository: disk).changes.remove(ids: [rows[1].id]))
        second.history.record(try useCases.changes.remove(ids: [rows[2].id]))
        second.history.undo()
        #expect(first.history.canUndo)
        #expect(second.history.canRedo)

        // A's Cmd-Z fails on a full disk, and its follow-up work is still queued when the restore lands.
        first.undoManager.afterAction = {}
        disk.isFull = true
        first.undoManager.undo()
        disk.isFull = false
        #expect(first.history.alert != nil)
        let revision = updates.revision

        _ = try await harness.service.restore(.stored(backup.id)) { _ in }
        first.settle()
        second.settle()

        for window in [first, second] {
            #expect(!window.history.canUndo)
            #expect(!window.history.canRedo)
            #expect(window.history.undoTitle == nil)
            #expect(window.history.redoTitle == nil)
            #expect(window.history.toast == nil)
            #expect(window.history.notice == nil)
            #expect(window.history.alert == nil)
            #expect(!window.undoManager.canUndo)
            #expect(!window.undoManager.canRedo)
        }
        #expect(updates.revision > revision)
        // Every row is back as it was in the backup.
        #expect(try Set(repository.transactions().map(\.id)) == Set(rows.map(\.id)))
        // Nothing left over runs again: a later Cmd-Z in either window does nothing.
        first.undoManager.undo()
        second.undoManager.redo()
        first.settle()
        second.settle()
        #expect(try Set(repository.transactions().map(\.id)) == Set(rows.map(\.id)))

        // The block really ended: a new edit after the restore can be undone, in both windows, including the one
        // whose Undo had failed.
        let windows = [(first, TransactionUseCases(repository: disk)), (second, useCases)]
        for (index, (window, cases)) in windows.enumerated() {
            window.history.record(try cases.changes.remove(ids: [rows[index].id]))
            #expect(window.history.canUndo)
            #expect(!(try repository.transactions().contains { $0.id == rows[index].id }))
            window.undoManager.undo()
            window.settle()
            #expect(window.history.alert == nil)
            #expect(try repository.transactions().contains { $0.id == rows[index].id })
        }
    }
}

extension BackupRestoreUndoTests {
    @Test("A stale Undo's message in one window doesn't survive the restore, and the step stays gone")
    func staleDoesNotSurvive() async throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 18))
        let repository = try F.repository([lunch])
        let harness = try BackupHarness(repository: repository)
        let backup = try await harness.service.backUpNow()
        let useCases = TransactionUseCases(repository: repository)
        let updates = LedgerUpdates()
        updates.follow(harness.changes)
        let first = TestWindow(useCases, updates: updates)
        let second = TestWindow(useCases, updates: updates)
        var edited = lunch
        edited.amount = 300
        first.history.record(try useCases.saveTransactions.save([edited]))
        // B deletes what A edited, so A's Undo is stale: it changes nothing, says why, and is dropped later.
        second.history.record(try useCases.changes.remove(ids: [lunch.id]))
        first.undoManager.afterAction = {}
        first.undoManager.undo()

        _ = try await harness.service.restore(.stored(backup.id)) { _ in }
        first.settle()
        for window in [first, second] {
            #expect(!window.history.canUndo && !window.history.canRedo)
            #expect(window.history.alert == nil)
            #expect(window.history.toast == nil)
        }
        #expect(try repository.transactions().first { $0.id == lunch.id }?.amount == 250)
    }
}

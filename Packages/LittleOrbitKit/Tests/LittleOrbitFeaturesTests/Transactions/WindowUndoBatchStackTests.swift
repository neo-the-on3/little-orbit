import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #285: a Bulk Edit's batch Undo beside ordinary steps, a Redo swallowed while it runs, and a history that goes
/// mid-batch (Tech Architect NB1, NB3 and NB4 on 5663375395).
@MainActor
@Suite("Window undo history: batch steps beside the others")
struct WindowUndoBatchStackTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name
    typealias Batch = WindowUndoBatchTests

    @Test("A mixed stack: Cmd-Z while the batch Undo runs applies nothing, the order holds, then Undo works (NB1)")
    func mixedStack() async throws {
        let rows = (0..<5).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let other = F.expense(42, on: F.date(2026, 10, 1))
        let disk = FullDiskLedgerRepository(try F.repository(rows + [other]))
        disk.hasBatchPath = true
        let useCases = TransactionUseCases(repository: disk, categoryNames: CatalogDefaultCategoryNames())
        let window = TestWindow(useCases)
        window.history.setScreen(.account(F.savingsID))
        var edited = other
        edited.details = "Synchronous"
        window.history.record(try useCases.saveTransactions.save([edited]))
        let syncName = try #require(window.undoManager.undoNames.last)
        var changes = BulkEditChanges()
        changes.details = .some("Bulk")
        let request = BulkEditRequest(
            selection: rows,
            changes: changes,
            payeeName: "",
            accounts: try disk.accounts(),
            timeZoneID: F.zoneID,
            now: F.now,
        )
        let change = try await useCases.bulkEdit.apply(request, reporting: .silent)
        window.history.record(change)
        window.history.markBulkEdit(change)
        #expect(window.undoManager.undoNames == [syncName, Batch.name])

        window.history.undo()
        // The Edit menu's own Undo while the batch runs: it pops the synchronous step, which goes back.
        window.undoManager.undo()
        window.settle()
        await window.history.batchRun?.task.value
        window.settle()
        #expect(window.undoManager.undoNames == [syncName])
        #expect(window.undoManager.redoNames == [Batch.name])
        let stored = { (id: UUID) in try disk.transactions().first { $0.id == id } }
        #expect(try stored(other.id)?.details == "Synchronous", "Cmd-Z applied nothing")
        #expect(try rows.allSatisfy { try stored($0.id)?.details == nil }, "The batch Undo ran")

        window.history.undo()
        #expect(try stored(other.id)?.details == nil, "The synchronous step undoes as before")
        #expect(window.undoManager.undoNames.isEmpty)
        #expect(window.undoManager.redoNames == [Batch.name, syncName])
    }

    @Test("A Redo swallowed while a batch Undo runs, then the batch fails: the step doesn't come back (NB4)")
    func swallowedRedoThenFailure() async throws {
        let setup = try await Batch.setup()
        // The stand-in finishes only when the test says, after the batch.
        setup.window.undoManager.afterAction = {}
        setup.disk.isFull = true
        setup.history.undo()
        setup.window.undoManager.redo()
        await setup.history.batchRun?.task.value
        setup.window.settle()
        #expect(try setup.stored() == setup.edited, "Nothing was written")
        #expect(setup.window.undoManager.undoNames.isEmpty)
        #expect(setup.window.undoManager.redoNames.isEmpty)
        #expect(setup.history.redoSteps.isEmpty && setup.history.undoSteps.isEmpty)
        #expect(setup.history.alert?.title == "Couldn’t Undo \(Batch.name)")
        #expect(!setup.history.isBatchRunning)
    }

    @Test("A Redo swallowed while a batch Undo runs that succeeds: the step is back on Redo once")
    func swallowedRedoThenSuccess() async throws {
        let setup = try await Batch.setup()
        setup.window.undoManager.afterAction = {}
        setup.history.undo()
        setup.window.undoManager.redo()
        await setup.history.batchRun?.task.value
        setup.window.settle()
        #expect(try setup.stored().allSatisfy { $0.details == nil })
        #expect(setup.window.undoManager.redoNames == [Batch.name])
        #expect(setup.history.canRedo)
    }

    @Test("A history that goes mid-batch, without cancelBatch: nothing is written and writes come back on (NB3)")
    func historyGoesMidBatch() async throws {
        let updates = LedgerUpdates()
        var setup: WindowUndoBatchTests.Setup? = try await Batch.setup(updates: updates)
        let disk = try #require(setup?.disk)
        let edited = try #require(setup?.edited)
        let ids = Set(edited.map(\.id))
        setup?.history.undo()
        let task = try #require(setup?.history.batchRun?.task)
        #expect(updates.isBatchRunning)
        weak let history = setup?.history
        setup = nil
        #expect(history == nil)
        await task.value
        #expect(!updates.isBatchRunning)
        #expect(try disk.transactions().filter { ids.contains($0.id) }.sorted { $0.date < $1.date } == edited)
    }
}

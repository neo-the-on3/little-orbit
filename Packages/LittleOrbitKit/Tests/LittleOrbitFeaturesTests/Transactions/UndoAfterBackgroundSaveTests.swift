import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #285, B (Tester2's N5: an Undo 0.13–0.31 s after the batch, while the table still refreshed). With the save off
/// the main actor, an Undo issued right after the Apply's save installed, while the register's off-main refresh
/// for that Apply is still pending, reads the installed ledger, writes once, and the register ends on the Undo's
/// result: the Apply's older refresh, finishing last, is dropped by the generation check.
@MainActor
@Suite("Undo right after a background save, with the register still refreshing")
struct UndoAfterBackgroundSaveTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @Test("The ledger and the register show exactly one Undo; the Apply's late refresh is dropped")
    func undoWhileRefreshPending() async throws {
        let rows = (0..<5).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let ids = Set(rows.map(\.id))
        let repository = try F.repository(rows)
        var backgroundSaves = 0
        repository.offMainSave = {
            backgroundSaves += 1
            await Task.yield()
        }
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let updates = LedgerUpdates()
        let window = TestWindow(useCases, updates: updates)
        window.history.setScreen(.account(F.savingsID))
        let builds = HeldRealBuilds()
        let register = AccountHistoryViewModel(
            useCases: useCases,
            accountID: F.savingsID,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        register.buildContent = builds.builder
        register.seenRevision = updates.revision
        register.load()
        let before = register.allRows

        // The Apply saves off the main actor and installs; its register refresh starts and is held.
        var changes = BulkEditChanges()
        changes.details = .some("Bulk")
        let request = BulkEditRequest(
            selection: try repository.transactions().filter { ids.contains($0.id) },
            changes: changes,
            payeeName: "",
            accounts: try repository.accounts(),
            timeZoneID: F.zoneID,
            now: F.now,
        )
        let change = try await useCases.bulkEdit.apply(request, reporting: .silent)
        window.history.record(change)
        window.history.markBulkEdit(change)
        #expect(backgroundSaves == 1)
        updates.changed()
        let applyRefresh = Task { await register.refresh(after: updates) }
        let applyBuild = await builds.next()

        // Undo right away, while that refresh is pending; a second Undo during its save does nothing.
        window.history.undo()
        #expect(window.history.isBatchRunning)
        window.history.undo()
        window.undoManager.undo()
        window.settle()
        await window.history.batchRun?.task.value
        #expect(backgroundSaves == 2, "One background save for the Undo, none for the refused ones")
        let undoRefresh = Task { await register.refresh(after: updates) }
        let undoBuild = await builds.next()

        // The Undo's refresh finishes first, the Apply's older one last.
        undoBuild.finish()
        await undoRefresh.value
        applyBuild.finish()
        await applyRefresh.value

        let stored = try repository.transactions().filter { ids.contains($0.id) }
        #expect(stored.allSatisfy { $0.details == nil }, "Reverted once")
        #expect(window.undoManager.undoNames.isEmpty)
        #expect(window.undoManager.redoNames.count == 1, "Exactly one Undo, on Redo once")
        #expect(window.history.alert == nil)
        #expect(register.allRows == before, "The register shows the Undo, not the Apply's refresh")
        #expect(register.seenRevision == updates.revision)
    }
}

/// Holds each refresh's build, then builds the real rows from the page it read when the test finishes it.
@MainActor
private final class HeldRealBuilds {
    private var started: [HeldRealBuild] = []
    private var waiting: [CheckedContinuation<HeldRealBuild, Never>] = []

    nonisolated var builder: AccountHistoryContentBuilder {
        { page, today, formatter, text in
            await self.hold()
            return AccountHistoryViewModel.content(of: page, today: today, formatter: formatter, text: text)
        }
    }

    func next() async -> HeldRealBuild {
        if !started.isEmpty {
            return started.removeFirst()
        }
        return await withCheckedContinuation { waiting.append($0) }
    }

    private func hold() async {
        await withCheckedContinuation { continuation in
            let build = HeldRealBuild(continuation)
            if waiting.isEmpty {
                started.append(build)
            } else {
                waiting.removeFirst().resume(returning: build)
            }
        }
    }
}

@MainActor
private final class HeldRealBuild {
    private let continuation: CheckedContinuation<Void, Never>

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func finish() {
        continuation.resume()
    }
}

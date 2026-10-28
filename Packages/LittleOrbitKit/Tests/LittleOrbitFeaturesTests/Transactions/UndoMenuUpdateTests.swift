import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// n2 on #201 (Tech Architect's spike (a)): after the items are read, the refresher has the menu bar apply them,
/// `updateMenu`, at every refresh and in the same call, so Edit › Undo's `NSMenuItem` is on as a batch ends rather
/// than about 0.65 s later. Whether the Edit menu delegate's `menuNeedsUpdate(_:)` does that is Tester2's on the
/// Mac; this checks the seam.
/// Mutants: dropping the `updateMenu()` call fails every test here; hopping it (`Task { @MainActor in }` or
/// `DispatchQueue.main.async`) fails them too, at once, since each checks before `refresh()` returns and none waits.
@MainActor
@Suite("Edit menu updated at every refresh, in the same call (n2)", .timeLimit(.minutes(1)))
struct UndoMenuUpdateTests {
    static let didClose = Notification.Name("test.n2.undoGroupDidClose")
    /// These tests post from the main actor, which on Linux isn't the main thread (on the Mac it is).
    static let main: @Sendable () -> Bool = { true }

    @Test("Every refresh, changed or not, updates the menu after `changed` and before it returns")
    func everyRefresh() async throws {
        try await UndoMenuRefresherTests.requirePostingThread()
        let center = NotificationCenter()
        let manager = FakeUndoManager()
        let log = Log()
        let refresher = UndoMenuRefresher(center: center, names: [Self.didClose], onMainThread: Self.main) {
            UndoMenuItems(manager, gateClosed: false)
        }
        refresher.changed = { log.events.append("changed \($0.canUndo)") }
        refresher.updateMenu = { [weak refresher] in
            log.events.append("update \(refresher?.items.canUndo ?? false)")
        }
        refresher.refresh()
        #expect(log.events == ["update false"], "Unchanged: still updated, before refresh() returns")
        manager.registerStep(manager, named: "Typing") {}
        refresher.refresh()
        #expect(log.events == ["update false", "changed true", "update true"], "After changed, with Undo on")
        center.post(name: Self.didClose, object: nil)
        #expect(log.events.count == 4, "A notification's refresh updates it before post returns")
    }

    @Test("The batch's end: the gate's refresh updates the menu with Undo on, before endBatch() returns")
    func batchEnd() {
        let gate = UndoCommandGate()
        gate.isTracking = { false }
        let updates = LedgerUpdates()
        updates.commandGate = gate
        let manager = FakeUndoManager()
        manager.registerStep(manager, named: "Edit 5 Transactions") {}
        let refresher = UndoMenuRefresher(center: NotificationCenter(), names: []) {
            UndoMenuItems(manager, gateClosed: gate.isClosed)
        }
        var seen: [(gateClosed: Bool, canUndo: Bool)] = []
        refresher.updateMenu = { [weak refresher] in
            seen.append((gate.isClosed, refresher?.items.canUndo ?? false))
        }
        gate.editMenuObserver = { [weak refresher] _ in refresher?.refresh() ?? UndoMenuItems(nil, gateClosed: true) }
        #expect(updates.beginBatch())
        #expect(seen.map(\.gateClosed) == [true])
        #expect(seen.last?.canUndo == false, "Dimmed as the batch starts")
        updates.endBatch()
        #expect(seen.map(\.gateClosed) == [true, false], "Updated in refreshMenu(\"end\"), in the same call")
        #expect(seen.last?.canUndo == true, "Undo on as the menu bar is updated")
    }

    @Test("A refresh the update itself sets off reads, but doesn't update the menu again")
    func noReentry() {
        let manager = FakeUndoManager()
        let refresher = UndoMenuRefresher(center: NotificationCenter(), names: []) {
            UndoMenuItems(manager, gateClosed: false)
        }
        var updates = 0
        refresher.updateMenu = { [weak refresher] in
            updates += 1
            manager.registerStep(manager, named: "Typing") {}
            refresher?.refresh()
        }
        refresher.refresh()
        #expect(updates == 1)
        #expect(refresher.items.canUndo, "The nested refresh still read the items")
        refresher.refresh()
        #expect(updates == 2, "The next refresh updates it again")
    }
}

/// What the hooks heard, in order, shared by reference with the `@MainActor` closures.
@MainActor
private final class Log {
    var events: [String] = []
}

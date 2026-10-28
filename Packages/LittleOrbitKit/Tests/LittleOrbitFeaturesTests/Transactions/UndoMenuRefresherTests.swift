import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// B1 on #201 (Tech Architect's n3): Edit › Undo's enabled state and title are current the moment an undo
/// notification posts, with no run-loop turn, so a ⌘Z right after the first keystroke finds Undo on. The batch
/// gate's closed state still wins. A private notification center and made-up names stand in for AppKit's.
/// Mutant: putting the main-queue hop back (`DispatchQueue.main.async` around the refresh) fails `readAtOnce`.
@MainActor
@Suite("Edit › Undo and Redo current at once (B1)", .timeLimit(.minutes(1)))
struct UndoMenuRefresherTests {
    static let didClose = Notification.Name("test.undoGroupDidClose")
    static let didUndo = Notification.Name("test.undoDidUndo")
    /// These tests post from the main actor, which on Linux isn't the main thread (on the Mac it is).
    static let main: @Sendable () -> Bool = { true }

    @Test("A group closes: canUndo and the title are read right away, before any run-loop turn")
    func readAtOnce() {
        let center = NotificationCenter()
        let manager = FakeUndoManager()
        var heard: [UndoMenuItems] = []
        let refresher = UndoMenuRefresher(
            center: center,
            names: [Self.didClose, Self.didUndo],
            onMainThread: Self.main,
        ) {
            UndoMenuItems(manager, gateClosed: false)
        }
        refresher.changed = { heard.append($0) }
        #expect(!refresher.items.canUndo)
        manager.registerStep(manager, named: "Typing") {}
        center.post(name: Self.didClose, object: nil)
        #expect(refresher.items.canUndo, "On in the same turn the group closed")
        #expect(refresher.items.undoTitle == "Undo Typing")
        #expect(heard.count == 1)
        center.post(name: Self.didClose, object: nil)
        #expect(heard.count == 1, "Unchanged: nothing more heard")
    }

    @Test("The gate's closed state still wins: dimmed while closed, on as it opens")
    func gateWins() {
        let center = NotificationCenter()
        let manager = FakeUndoManager()
        var closed = true
        let refresher = UndoMenuRefresher(center: center, names: [Self.didClose], onMainThread: Self.main) {
            UndoMenuItems(manager, gateClosed: closed)
        }
        manager.registerStep(manager, named: "Typing") {}
        center.post(name: Self.didClose, object: nil)
        #expect(!refresher.items.canUndo, "Closed: still dimmed")
        #expect(refresher.items.undoTitle == "Undo Typing")
        closed = false
        refresher.refresh()
        #expect(refresher.items.canUndo)
    }

    @Test("Only the names it observes refresh it")
    func otherNamesIgnored() {
        let center = NotificationCenter()
        let manager = FakeUndoManager()
        let refresher = UndoMenuRefresher(center: center, names: [Self.didClose], onMainThread: Self.main) {
            UndoMenuItems(manager, gateClosed: false)
        }
        manager.registerStep(manager, named: "Typing") {}
        center.post(name: Notification.Name("test.checkpoint"), object: nil)
        #expect(!refresher.items.canUndo, "A checkpoint-like name isn't observed (Tester's B1 on #87)")
    }
}

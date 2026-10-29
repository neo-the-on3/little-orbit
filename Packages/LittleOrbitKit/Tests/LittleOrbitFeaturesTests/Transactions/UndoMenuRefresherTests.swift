import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// B1 on #201 (Tech Architect's n3): Edit › Undo's enabled state and title are current the moment an undo
/// notification posts, with no run-loop turn, so a ⌘Z right after the first keystroke finds Undo on. The batch
/// gate's closed state still wins. A private notification center and made-up names stand in for AppKit's.
/// Mutants: putting the main-queue hop back (`DispatchQueue.main.async` around the refresh, or a `Task` hop) fails
/// `readAtOnce`. Observing with `queue: .main` fails `requirePostingThread` in every test within seconds: posted
/// from the main actor, a real center would wait on Linux for a main queue that the test's own turn is holding.
@MainActor
@Suite("Edit › Undo and Redo current at once (B1)", .timeLimit(.minutes(1)))
struct UndoMenuRefresherTests {
    static let didClose = Notification.Name("test.undoGroupDidClose")
    static let didUndo = Notification.Name("test.undoDidUndo")
    /// These tests post from the main actor, which on Linux isn't the main thread (on the Mac it is).
    static let main: @Sendable () -> Bool = { true }

    @Test("A group closes: canUndo and the title are read right away, before any run-loop turn")
    func readAtOnce() async throws {
        try await Self.requirePostingThread()
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
    func gateWins() async throws {
        try await Self.requirePostingThread()
        let center = NotificationCenter()
        let manager = FakeUndoManager()
        let gate = GateState()
        let refresher = UndoMenuRefresher(center: center, names: [Self.didClose], onMainThread: Self.main) {
            UndoMenuItems(manager, gateClosed: gate.closed)
        }
        manager.registerStep(manager, named: "Typing") {}
        center.post(name: Self.didClose, object: nil)
        #expect(!refresher.items.canUndo, "Closed: still dimmed")
        #expect(refresher.items.undoTitle == "Undo Typing")
        gate.closed = false
        refresher.refresh()
        #expect(refresher.items.canUndo)
    }

    @Test("Only the names it observes refresh it")
    func otherNamesIgnored() async throws {
        try await Self.requirePostingThread()
        let center = NotificationCenter()
        let manager = FakeUndoManager()
        let refresher = UndoMenuRefresher(center: center, names: [Self.didClose], onMainThread: Self.main) {
            UndoMenuItems(manager, gateClosed: false)
        }
        manager.registerStep(manager, named: "Typing") {}
        center.post(name: Notification.Name("test.checkpoint"), object: nil)
        #expect(!refresher.items.canUndo, "A checkpoint-like name isn't observed (Tester's B1 on #87)")
    }

    /// What a probe post from another thread saw: the observer asked `onMainThread` (on the posting thread or not),
    /// then `post` returned.
    private enum ProbeEvent: Equatable, Sendable {
        case observed(onPostingThread: Bool)
        case posted
    }

    /// Fails, and stops the test before it posts from the main actor, unless the refresher observes on the posting
    /// thread. The probe posts from its own thread, so a queue hop can't hold up the main actor: the observer then
    /// runs elsewhere, or `post` never returns and the 5-second bound ends the wait. A passing run never waits on it.
    /// The posting thread is known by a token in its own thread dictionary, not by its name: on Linux, reading
    /// `Thread.current.name` back on the thread that set it sometimes gives something else (#303: 9 of 50 runs of
    /// these suites failed with `observed(onPostingThread: false)` in a few milliseconds).
    static func requirePostingThread() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("test.postingThreadProbe")
        let key = "lo.b1.poster"
        let token = UUID().uuidString
        let (events, sink) = AsyncStream.makeStream(of: ProbeEvent.self)
        let refresher = UndoMenuRefresher(center: center, names: [name]) {
            sink.yield(.observed(onPostingThread: Thread.current.threadDictionary[key] as? String == token))
            return false
        } read: {
            UndoMenuItems(FakeUndoManager(), gateClosed: false)
        }
        let thread = Thread {
            Thread.current.threadDictionary[key] = token
            center.post(name: name, object: nil)
            sink.yield(.posted)
            sink.finish()
        }
        thread.start()
        let bound = Task {
            try? await Task.sleep(for: .seconds(5))
            sink.finish()
        }
        var seen: [ProbeEvent] = []
        for await event in events {
            seen.append(event)
        }
        bound.cancel()
        withExtendedLifetime(refresher) {}
        try #require(
            seen == [.observed(onPostingThread: true), .posted],
            "The observer runs on the posting thread before post returns (no queue: .main)",
        )
    }
}

/// The batch gate's closed state, shared by reference with the `@MainActor` read closure.
@MainActor
private final class GateState {
    var closed = true
}

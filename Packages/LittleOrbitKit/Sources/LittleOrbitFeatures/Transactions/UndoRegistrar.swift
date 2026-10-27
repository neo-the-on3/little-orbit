import Foundation
import Observation

/// What a window's undo history needs from the window's `UndoManager` (`@Environment(\.undoManager)`). The
/// `UndoManager` holds the window's steps; the history registers each one on it and nothing else (D187.2).
/// The tests use a stand-in, because Linux, where CI also runs them, has no `UndoManager`.
@MainActor
public protocol UndoRegistrar: AnyObject {
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    var isUndoing: Bool { get }
    var isRedoing: Bool { get }
    /// How many groups are open; 0 between events.
    var groupingLevel: Int { get }
    /// The newest Undo and Redo names, "" when there are none.
    var undoActionName: String { get }
    var redoActionName: String { get }
    /// Registers one undoable step for `target` with its name: on Undo while not undoing, on Redo while
    /// undoing, as `UndoManager` does.
    func registerStep(_ target: AnyObject, named name: String, handler: @escaping @MainActor () -> Void)
    /// Removes every Undo and Redo step registered for `target`.
    func removeSteps(for target: AnyObject)
    func undo()
    func redo()
    /// Calls `onChange` after the Undo or Redo lists may have changed: a group opened or closed, an Undo or a
    /// Redo. Never on a checkpoint, which merely reading `canUndo` or `canRedo` posts (B1). The result keeps
    /// the observation alive; dropping it stops it.
    func observeChanges(_ onChange: @escaping @MainActor (UndoEvent) -> Void) -> AnyObject
}

/// What happened on a window's `UndoManager`, from its notifications.
public enum UndoEvent: Equatable, Sendable {
    case openedGroup
    case closedGroup
    case undid
    case redid
}

#if canImport(Darwin)
    extension UndoManager: UndoRegistrar {
        public func registerStep(
            _ target: AnyObject,
            named name: String,
            handler: @escaping @MainActor () -> Void,
        ) {
            // The window's own settings, grouping by event included, are left as the system set them.
            registerUndo(withTarget: target) { _ in
                MainActor.assumeIsolated { handler() }
            }
            setActionName(name)
        }

        public func removeSteps(for target: AnyObject) {
            removeAllActions(withTarget: target)
        }

        public func observeChanges(_ onChange: @escaping @MainActor (UndoEvent) -> Void) -> AnyObject {
            // Not `NSUndoManagerCheckpoint`: reading `canUndo` or `canRedo` posts it, so a toolbar that read them
            // and redrew on it would never stop (Tester's B1 on #87).
            let events: [(Notification.Name, UndoEvent)] = [
                (.NSUndoManagerDidOpenUndoGroup, .openedGroup),
                (.NSUndoManagerDidCloseUndoGroup, .closedGroup),
                (.NSUndoManagerDidUndoChange, .undid),
                (.NSUndoManagerDidRedoChange, .redid),
            ]
            let center = NotificationCenter.default
            let tokens = events.map { name, event in
                center.addObserver(forName: name, object: self, queue: nil) { _ in
                    MainActor.assumeIsolated { onChange(event) }
                }
            }
            return UndoObservation(tokens: tokens)
        }
    }

    /// Removes the notification observers when the window's history lets go of it.
    final class UndoObservation {
        private let tokens: [any NSObjectProtocol]

        init(tokens: [any NSObjectProtocol]) {
            self.tokens = tokens
        }

        deinit {
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }
#endif

/// Moves on after every change to the one shared store from any window, so every window's lists and
/// balances reload straight away (D187.4). Built once, at App level.
@MainActor
@Observable
public final class LedgerUpdates {
    public private(set) var revision = 0
    /// A Bulk Edit, or its Undo or Redo, is being built or saved in some window. Until it ends, every window's
    /// ledger writes are off, Undo and Redo included; nothing queues (#285, D398).
    public private(set) var isBatchRunning = false
    @ObservationIgnored private var histories: [WeakHistory] = []
    @ObservationIgnored private var replacedHandlers: [(id: UUID, run: @MainActor () -> Void)] = []
    @ObservationIgnored private var changedHandlers: [@MainActor () -> Void] = []

    private struct WeakHistory {
        weak var history: WindowUndoHistory?
    }

    public init() {}

    /// Starts a batch: writes go off in every window. `false` when one is already running, which starts nothing.
    func beginBatch() -> Bool {
        guard !isBatchRunning else {
            return false
        }
        isBatchRunning = true
        refreshHistories()
        return true
    }

    func endBatch() {
        guard isBatchRunning else {
            return
        }
        isBatchRunning = false
        refreshHistories()
    }

    private func refreshHistories() {
        for entry in histories {
            entry.history?.refreshMenu()
        }
    }

    func changed() {
        revision += 1
        runChangedHandlers()
    }

    /// Runs `handler` after every change and every restore, for state kept outside the ledger that follows it, such
    /// as the Scheduled reminders (#26, D340.7). Registered once per launch.
    func onChanged(_ handler: @escaping @MainActor () -> Void) {
        changedHandlers.append(handler)
    }

    private func runChangedHandlers() {
        for handler in changedHandlers {
            handler()
        }
    }

    /// One `onLedgerReplaced` handler, for removing it again.
    struct ReplacedHandler: Hashable {
        fileprivate let id: UUID
    }

    /// Runs `handler` on every restore, before the reload, for state kept beside the ledger, such as the
    /// Scheduled catch-up hint (#26). Something registered per window, rather than once per launch, removes its
    /// handler with the returned token when it goes (Tech Architect NB 3).
    @discardableResult
    func onLedgerReplaced(_ handler: @escaping @MainActor () -> Void) -> ReplacedHandler {
        let token = ReplacedHandler(id: UUID())
        replacedHandlers.append((token.id, handler))
        return token
    }

    /// Stops running a handler from `onLedgerReplaced`. Removing it twice does nothing.
    func removeLedgerReplacedHandler(_ token: ReplacedHandler) {
        replacedHandlers.removeAll { $0.id == token.id }
    }

    func add(_ history: WindowUndoHistory) {
        histories.removeAll { $0.history == nil }
        histories.append(WeakHistory(history: history))
    }

    /// The whole ledger was replaced outside any window, by a backup restore (#40, #99). Every window's
    /// history is cleared, since its steps were made against the old data (D187.2), and every window reloads.
    public func ledgerReplaced() {
        for entry in histories {
            entry.history?.clear()
            // A failed or stale Undo's alert is about a step that's gone now, so it doesn't outlive the old data
            // (Tech Architect N6).
            entry.history?.alert = nil
        }
        for handler in replacedHandlers {
            handler.run()
        }
        revision += 1
        runChangedHandlers()
    }
}

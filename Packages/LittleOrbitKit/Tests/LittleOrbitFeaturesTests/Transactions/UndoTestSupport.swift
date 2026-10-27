import Foundation
import LittleOrbitDomain

@testable import LittleOrbitFeatures

/// Stands in for a window's `UndoManager` on every platform, Linux included, with the same rules: a step
/// registered while undoing goes on Redo, while redoing on Undo, and otherwise on Undo, clearing Redo. A
/// handler that registers nothing leaves an empty group behind. The macOS-only suites check the real one.
@MainActor
final class FakeUndoManager: UndoRegistrar {
    private struct Entry {
        let target: ObjectIdentifier
        let name: String
        let handler: @MainActor () -> Void
    }

    /// Runs after each Undo or Redo returns, as the window's next event does.
    var afterAction: () -> Void = {}
    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []
    private var collected: [Entry]?
    private var onChange: @MainActor (UndoEvent) -> Void = { _ in }
    private(set) var isUndoing = false
    private(set) var isRedoing = false
    let groupingLevel = 0

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoActionName: String { undoStack.last?.name ?? "" }
    var redoActionName: String { redoStack.last?.name ?? "" }
    var undoCount: Int { undoStack.count }
    /// Every name on each list, oldest first.
    var undoNames: [String] { undoStack.map(\.name) }
    var redoNames: [String] { redoStack.map(\.name) }

    func registerStep(_ target: AnyObject, named name: String, handler: @escaping @MainActor () -> Void) {
        let entry = Entry(target: ObjectIdentifier(target), name: name, handler: handler)
        if collected != nil {
            collected?.append(entry)
            return
        }
        undoStack.append(entry)
        redoStack.removeAll()
        onChange(.openedGroup)
    }

    func removeSteps(for target: AnyObject) {
        undoStack.removeAll { $0.target == ObjectIdentifier(target) }
        redoStack.removeAll { $0.target == ObjectIdentifier(target) }
        onChange(.closedGroup)
    }

    func undo() {
        guard let entry = undoStack.popLast() else {
            return
        }
        isUndoing = true
        redoStack += run(entry)
        isUndoing = false
        onChange(.undid)
        afterAction()
    }

    func redo() {
        guard let entry = redoStack.popLast() else {
            return
        }
        isRedoing = true
        undoStack += run(entry)
        isRedoing = false
        onChange(.redid)
        afterAction()
    }

    /// A handler that registers nothing leaves an empty group, as on the real one: a dead entry named "".
    private func run(_ entry: Entry) -> [Entry] {
        collected = []
        entry.handler()
        defer { collected = nil }
        let registered = collected ?? []
        return registered.isEmpty ? [Entry(target: ObjectIdentifier(Self.self), name: "", handler: {})] : registered
    }

    /// Like the real one's group, Undo and Redo notifications.
    func observeChanges(_ onChange: @escaping @MainActor (UndoEvent) -> Void) -> AnyObject {
        self.onChange = onChange
        return self
    }

    /// Something else in the window registers, e.g. typing in a text field (W5).
    func registerTyping() {
        registerStep(NSObject(), named: "Typing") {}
    }
}

/// One window over the shared store: its history and its `UndoManager`, which the window owns.
@MainActor
final class TestWindow {
    let undoManager = FakeUndoManager()
    let history: WindowUndoHistory
    private(set) var announcements: [String] = []
    private var pending: [@MainActor () -> Void] = []

    init(_ useCases: TransactionUseCases, updates: LedgerUpdates = LedgerUpdates()) {
        var queue: (@escaping @MainActor () -> Void) -> Void = { _ in }
        history = WindowUndoHistory(
            changes: useCases.changes,
            loadLedger: useCases.loadLedger,
            updates: updates,
            later: { queue($0) },
        )
        // Weak, not unowned: a test that fails early returns while its batch still runs, and the batch's end then
        // reaches these after the window has gone. An unowned read of a freed window aborted the whole test process
        // with signal 6 (Tester2 on 0d676f8, LedgerRefreshRegistrationTests, Release run 2).
        queue = { [weak self] in self?.pending.append($0) }
        history.attach(undoManager)
        // A clock that stands still, and no sheet timer at all: a slow parallel run mustn't show a batch's
        // sheet, which holds its announcement. A sheet still shows when `BatchSheetPolicy` asks for one before the
        // save (Tech Architect's review 5666870090).
        let instant = ContinuousClock.now
        history.progressClock = { instant }
        history.progressShowDelay = nil
        history.announce = { [weak self] in self?.announcements.append($0) }
        undoManager.afterAction = { [weak self] in self?.settle() }
    }

    /// Runs what was left for after the current Undo or Redo; the stand-in `UndoManager` calls it.
    func settle() {
        let work = pending
        pending.removeAll()
        for job in work {
            job()
        }
    }
}

/// Undo in the view-model tests goes through a window's history, the app's only undo path (D187.2).
@MainActor
enum UndoTestSupport {
    /// Records `change` in a new window and undoes it; returns the window, so Redo can follow.
    @discardableResult
    static func undo(_ change: TransactionChange, useCases: TransactionUseCases) -> TestWindow {
        let window = TestWindow(useCases)
        window.history.record(change)
        window.history.undo()
        return window
    }
}

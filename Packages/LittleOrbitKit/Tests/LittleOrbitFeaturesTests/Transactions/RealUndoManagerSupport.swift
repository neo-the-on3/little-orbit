#if canImport(SwiftUI) && os(macOS)
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitFeatures

    /// A window on a real `UndoManager`, with the system's settings (grouping by event on). The macOS CI job
    /// runs these; the rest of the undo tests use `FakeUndoManager`.
    @MainActor
    final class RealWindow {
        let undoManager = UndoManager()
        let history: WindowUndoHistory
        private var pending: [@MainActor () -> Void] = []

        init(_ useCases: TransactionUseCases, updates: LedgerUpdates = LedgerUpdates()) {
            var queue: (@escaping @MainActor () -> Void) -> Void = { _ in }
            history = WindowUndoHistory(
                changes: useCases.changes,
                loadLedger: useCases.loadLedger,
                updates: updates,
                later: { queue($0) },
            )
            // Weak, as in `TestWindow`: something left for later after the window has gone is dropped, not read
            // through a freed reference (Tech Architect's n5 on bab2ad8).
            queue = { [weak self] in self?.pending.append($0) }
            history.attach(undoManager)
        }

        /// Lets the run loop turn once, as it does between two taps, so the event's automatic group closes,
        /// then runs what was left for after the Undo or Redo.
        func nextEvent() {
            RunLoop.current.add(Timer(timeInterval: 0.02, repeats: false) { _ in }, forMode: .default)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let work = pending
            pending.removeAll()
            for job in work {
                job()
            }
            if !work.isEmpty {
                nextEvent()
            }
        }

        /// Records a change the way a tap does: in its own event.
        @discardableResult
        func record(_ change: TransactionChange) -> UUID {
            let id = history.record(change)
            nextEvent()
            return id
        }

        /// Cmd-Z and Shift-Cmd-Z, each in its own event.
        func undo() {
            undoManager.undo()
            nextEvent()
        }

        func redo() {
            undoManager.redo()
            nextEvent()
        }
    }
#endif

#if canImport(SwiftUI) && os(macOS)
    import AppKit
    import Foundation
    import LittleOrbitDomain
    import Observation
    import SwiftUI
    import Testing

    @testable import LittleOrbitFeatures

    /// Tester's B1 on #87: reading `canRedo` on a real `UndoManager` posts `NSUndoManagerCheckpoint`. A toolbar
    /// that read it while drawing, and redrew on that notification, never stopped. The toolbar now reads
    /// state the history keeps, which only the `UndoManager`'s group, Undo and Redo notifications update.
    @MainActor
    @Suite("B1: the toolbar's Undo and Redo don't feed back", .timeLimit(.minutes(2)))
    struct UndoToolbarFeedbackTests {
        typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

        /// Set from `withObservationTracking`'s change handler.
        final class Flag: @unchecked Sendable {
            var raised = false
        }

        /// Counts how often the probe's body runs.
        final class Counter {
            var bodies = 0
        }

        /// The account toolbar's reads: both titles and both enabled states.
        struct ToolbarProbe: View {
            @Environment(WindowUndoHistory.self) private var history
            let counter: Counter

            var body: some View {
                counter.bodies += 1
                return HStack {
                    Button(history.undoTitle.map { "Undo \($0)" } ?? "Undo") {}
                        .disabled(!history.canUndo)
                    Button(history.redoTitle.map { "Redo \($0)" } ?? "Redo") {}
                        .disabled(!history.canRedo)
                }
            }
        }

        private func pump(_ seconds: TimeInterval = 0.3) {
            RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        }

        @Test("Reading Undo and Redo, on the history or the UndoManager, changes no observed state")
        func readingChangesNothing() throws {
            let corner = F.expense(450, on: F.date(2026, 10, 18), details: "Corner Bakery")
            let tea = F.expense(20, on: F.date(2026, 10, 18))
            let repository = try F.repository([corner, tea])
            let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
            let window = RealWindow(useCases)
            window.record(try useCases.changes.remove(ids: [corner.id]))
            window.record(try useCases.changes.remove(ids: [tea.id]))
            window.undo()
            let history = window.history
            #expect(history.canUndo && history.canRedo)

            let flag = Flag()
            withObservationTracking {
                _ = (history.canUndo, history.canRedo, history.undoTitle, history.redoTitle)
            } onChange: {
                flag.raised = true
            }
            for _ in 0..<50 {
                _ = (window.undoManager.canUndo, window.undoManager.canRedo)
                _ = (window.undoManager.undoActionName, window.undoManager.redoActionName)
                _ = (history.canUndo, history.canRedo, history.undoTitle, history.redoTitle)
            }
            window.nextEvent()
            #expect(!flag.raised, "A read is never a change")
            #expect(history.undoTitle != nil && history.undoTitle == window.undoManager.undoActionName)
            #expect(history.redoTitle != nil && history.redoTitle == window.undoManager.redoActionName)
        }

        @Test("A window showing the toolbar draws a few times and then stops, before and after a change")
        func bodyEvaluationsSettle() throws {
            let corner = F.expense(450, on: F.date(2026, 10, 18), details: "Corner Bakery")
            let repository = try F.repository([corner])
            let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
            let history = WindowUndoHistory(
                changes: useCases.changes,
                loadLedger: useCases.loadLedger,
                updates: LedgerUpdates(),
            )
            let counter = Counter()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
                styleMask: [.titled],
                backing: .buffered,
                defer: false,
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ToolbarProbe(counter: counter).undoWindow(history) { _ in })
            window.contentView?.layoutSubtreeIfNeeded()
            pump()
            window.contentView?.layoutSubtreeIfNeeded()
            pump()
            let opened = counter.bodies
            #expect(opened > 0)
            #expect(opened < 10, "Opening draws a bounded number of times")

            history.record(try useCases.changes.remove(ids: [corner.id]))
            pump()
            window.contentView?.layoutSubtreeIfNeeded()
            pump()
            #expect(history.canUndo, "The window's own UndoManager holds the step")
            let changed = counter.bodies
            #expect(changed - opened < 10)
            pump(0.5)
            window.contentView?.layoutSubtreeIfNeeded()
            pump(0.5)
            #expect(counter.bodies == changed, "No more drawing once nothing changes")
            window.close()
        }
    }
#endif

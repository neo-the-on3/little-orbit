#if canImport(SwiftUI) && os(macOS)
    import AppKit
    import Combine
    import SwiftUI

    /// Edit > Undo and Redo, named and enabled from the undo manager ⌘Z actually reaches (D288.3, D290.2, UI
    /// Designer on #201): the key window's first responder's `undoManager`, else the window's. While someone types in the pay
    /// sheet's amount field that's the field's, so the menu reads "Undo Typing"; elsewhere it's the window's,
    /// "Undo Pay Phone Plan"; and each item dims when its manager has nothing to undo or redo, or while a batch runs
    /// (D407.1, #293). The SwiftUI app's own items show no action name, so these replace them. Each item runs only
    /// through the batch gate (`UndoCommandGate.perform`, D403.1), which sends the standard `undo:` or `redo:` down
    /// the responder chain, so whatever has focus handles it exactly as before (D407.6); only the title and the
    /// enabled state are the app's.
    @MainActor
    public struct UndoRedoCommands: Commands {
        // Observed as an `ObservableObject`, so the items are redrawn when the focused manager changes.
        @ObservedObject private var menu = FocusedUndoMenu.shared

        public init() {}

        public var body: some Commands {
            CommandGroup(replacing: .undoRedo) {
                Button(menu.items.undoTitle) {
                    UndoCommandGate.shared.perform(.undo, send: Self.send)
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!menu.items.canUndo)
                Button(menu.items.redoTitle) {
                    UndoCommandGate.shared.perform(.redo, send: Self.send)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!menu.items.canRedo)
            }
        }

        /// The command's `undo:` or `redo:` down the responder chain, through the app's `NSApplication`, whose
        /// guard refuses it while the gate is closed (`LittleOrbitApplication.sendAction(_:to:from:)`).
        private static func send(_ command: UndoCommandGate.Command) -> Bool {
            NSApp.sendAction(command.action, to: nil, from: nil)
        }
    }

    /// The Edit menu's items, read again whenever they may have changed: a group opened or closed, an Undo or a Redo
    /// on any undo manager, a window becoming or leaving key, the menu bar opening (menu update), and the batch gate
    /// closing or opening (`UndoCommandGate.editMenuObserver`, read in the same turn, D407.2). Never on
    /// `NSUndoManagerCheckpoint`, which reading `canUndo` posts (Tester's B1 on #87).
    @MainActor
    final class FocusedUndoMenu: ObservableObject {
        static let shared = FocusedUndoMenu()

        @Published private(set) var items = UndoMenuItems(nil, gateClosed: false)
        private var tokens: [any NSObjectProtocol] = []

        private init() {
            let names: [Notification.Name] = [
                .NSUndoManagerDidOpenUndoGroup,
                .NSUndoManagerDidCloseUndoGroup,
                .NSUndoManagerDidUndoChange,
                .NSUndoManagerDidRedoChange,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSMenu.didBeginTrackingNotification,
            ]
            tokens = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
            UndoCommandGate.shared.editMenuObserver = { [weak self] gateClosed in
                self?.refresh(gateClosed: gateClosed) ?? UndoMenuItems(nil, gateClosed: gateClosed)
            }
            refresh()
        }

        /// `refresh(gateClosed:)` for the gate as it is now.
        func refresh() {
            refresh(gateClosed: UndoCommandGate.shared.isClosed)
        }

        /// For the manager ⌘Z reaches, as `NSApp.sendAction(undo:, to: nil, from: nil)` finds it: the key window's
        /// first responder's `undoManager`, else the key window's (`UndoMenuItems`).
        @discardableResult
        func refresh(gateClosed: Bool) -> UndoMenuItems {
            let window = NSApp?.keyWindow
            let manager = window?.firstResponder?.undoManager ?? window?.undoManager
            let next = UndoMenuItems(manager, gateClosed: gateClosed)
            if next != items {
                items = next
            }
            return next
        }
    }
#endif

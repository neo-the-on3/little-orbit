#if canImport(SwiftUI) && os(macOS)
    import AppKit
    import Combine
    import SwiftUI

    /// Edit > Undo and Redo, named and enabled from the undo manager ⌘Z actually reaches (D285.5, UI Designer on
    /// #201): the key window's first responder's `undoManager`, else the window's. While someone types in the pay
    /// sheet's amount field that's the field's, so the menu reads "Undo Typing"; elsewhere it's the window's,
    /// "Undo Pay Phone Plan"; and each item dims when its manager has nothing to undo or redo. The SwiftUI app's own
    /// items show no action name, so these replace them. Each item still sends the standard `undo:` or `redo:` down
    /// the responder chain, so whatever has focus handles it exactly as before; only the title and the enabled
    /// state are the app's.
    @MainActor
    public struct UndoRedoCommands: Commands {
        // Observed as an `ObservableObject`, so the items are redrawn when the focused manager changes.
        @ObservedObject private var menu = FocusedUndoMenu.shared

        public init() {}

        public var body: some Commands {
            CommandGroup(replacing: .undoRedo) {
                Button(menu.items.undoTitle) {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!menu.items.canUndo)
                Button(menu.items.redoTitle) {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!menu.items.canRedo)
            }
        }
    }

    /// The Edit menu's items, read again whenever they may have changed: a group opened or closed, an Undo or a Redo
    /// on any undo manager, a window becoming or leaving key, and the menu bar opening (menu update). Never on
    /// `NSUndoManagerCheckpoint`, which reading `canUndo` posts (Tester's B1 on #87).
    @MainActor
    final class FocusedUndoMenu: ObservableObject {
        static let shared = FocusedUndoMenu()

        @Published private(set) var items = UndoMenuItems(nil)
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
            refresh()
        }

        /// The first responder's undo manager, as ⌘Z finds it, else the key window's.
        func refresh() {
            let window = NSApp?.keyWindow
            let manager = window?.firstResponder?.undoManager ?? window?.undoManager
            let next = UndoMenuItems(manager)
            if next != items {
                items = next
            }
        }
    }
#endif

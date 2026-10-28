import Foundation

/// Whether the app's key-down monitor should run ⌘Z or ⇧⌘Z itself (n2 on #201, Tech Architect's option (d)).
///
/// Edit › Undo and Redo are SwiftUI items, and SwiftUI applies their `.disabled` to the `NSMenuItem` 0.1–0.3 s after
/// the batch gate opens (Tester2 at e9e9945, 18bf9f2 and decb793). A ⌘Z in that window meets a disabled item:
/// AppKit beeps, and neither the gate nor the queued-key drop is ever asked. So the monitor acts only when the item
/// is behind: the item is disabled, the gate is open, and the undo manager ⌘Z reaches can undo (or redo). Then it
/// sends the command as the menu item would (`UndoCommandGate.perform`, then `undo:` or `redo:` down the responder
/// chain), so a ⌘Z queued during the batch is still dropped by its key-down's time (D403) and a focused text field
/// still undoes its own typing. In every other case it leaves the event to AppKit, so an enabled item is never run
/// twice and a closed gate still beeps (D407.1).
///
/// A text field being edited: `canUndo` and `canRedo` are read from the key window's first responder's
/// `undoManager`, as `UndoMenuItems` reads them, so with the field editor first responder they're the field's
/// typing. The decision doesn't need to know a field has focus: when it acts, `undo:` with no target reaches the
/// field first, which undoes the typing, not the ledger.
///
/// Platform-neutral, so the whole decision is tested on Linux; the Mac part only fills in `Input`
/// (`UndoKeyMonitor`).
enum UndoKeyPolicy {
    /// The key-down's modifiers, `NSEvent.ModifierFlags.deviceIndependentFlagsMask` without Caps Lock. Any flag
    /// not named here is `other`.
    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)
        static let function = Modifiers(rawValue: 1 << 4)
        static let other = Modifiers(rawValue: 1 << 5)
    }

    /// What the monitor sees as a key-down arrives.
    struct Input: Equatable, Sendable {
        /// `charactersIgnoringModifiers`: "z" for ⌘Z; "Z" for ⇧⌘Z, as Shift still applies there.
        var characters: String?
        var modifiers: Modifiers
        /// Whether the event's window is one of the app's own and is key.
        var isAppKeyWindow: Bool
        /// Whether a menu is tracking (`UndoCommandGate.mainIsTracking()`).
        var isMenuTracking: Bool
        /// `UndoCommandGate.isClosed`.
        var gateClosed: Bool
        /// Whether the undo manager ⌘Z reaches can undo or redo, the gate aside.
        var canUndo: Bool
        var canRedo: Bool
        /// Edit › Undo's and Redo's `NSMenuItem.isEnabled`; `nil` when the item can't be found, which never acts.
        var undoItemEnabled: Bool?
        var redoItemEnabled: Bool?
    }

    enum Decision: Equatable, Sendable {
        /// Leave the event to AppKit.
        case pass
        /// Run the command through the gate and consume the event.
        case act(UndoCommandGate.Command)
    }

    /// The command a key is: ⌘Z exactly is Undo, ⇧⌘Z exactly is Redo; anything else, ⌥ or ⌃ added among them, none.
    static func command(characters: String?, modifiers: Modifiers) -> UndoCommandGate.Command? {
        guard characters?.lowercased() == "z" else {
            return nil
        }
        switch modifiers {
        case [.command]: return .undo
        case [.command, .shift]: return .redo
        default: return nil
        }
    }

    /// Acts only when every one holds: the key is ⌘Z or ⇧⌘Z exactly, in the app's key window, with no menu
    /// tracking, the gate open, the manager able to run it, and its menu item disabled.
    static func decide(_ input: Input) -> Decision {
        guard let command = command(characters: input.characters, modifiers: input.modifiers),
            input.isAppKeyWindow,
            !input.isMenuTracking,
            !input.gateClosed
        else {
            return .pass
        }
        let (can, itemEnabled) =
            switch command {
            case .undo: (input.canUndo, input.undoItemEnabled)
            case .redo: (input.canRedo, input.redoItemEnabled)
            }
        guard can, itemEnabled == false else {
            return .pass
        }
        return .act(command)
    }
}

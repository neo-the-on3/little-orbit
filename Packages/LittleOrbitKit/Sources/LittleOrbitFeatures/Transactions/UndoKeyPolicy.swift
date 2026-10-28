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

    /// Why the monitor acted or passed, signposted on every pass in Debug builds as `ledger.keyMonitor.pass`
    /// (Tester2 at 7c8a893), in the order `reason(_:)` checks them.
    enum Reason: String, CaseIterable, Sendable {
        /// `charactersIgnoringModifiers` isn't "z" or "Z".
        case notZ
        /// Z, but the modifiers aren't exactly ⌘ or ⇧⌘.
        case flagsMismatch
        /// The event's window isn't one of the app's own, or isn't key.
        case notKeyWindow
        /// A menu is tracking.
        case tracking
        /// The gate is closed: a batch is running, or a menu holds it.
        case gateClosed
        /// The undo manager ⌘Z reaches can't run the command.
        case cannotRun
        /// The command's Edit menu item can't be found.
        case noItem
        /// The item is enabled already, so AppKit's menu runs it.
        case itemEnabled
        /// The item lags disabled with the gate open: the monitor runs it.
        case act

        /// The signpost tag, which must be a static string: the case's name.
        var tag: StaticString {
            switch self {
            case .notZ: "notZ"
            case .flagsMismatch: "flagsMismatch"
            case .notKeyWindow: "notKeyWindow"
            case .tracking: "tracking"
            case .gateClosed: "gateClosed"
            case .cannotRun: "cannotRun"
            case .noItem: "noItem"
            case .itemEnabled: "itemEnabled"
            case .act: "act"
            }
        }
    }

    /// The command a key is: ⌘Z exactly is Undo, ⇧⌘Z exactly is Redo; anything else, ⌥ or ⌃ added among them, none.
    static func command(characters: String?, modifiers: Modifiers) -> UndoCommandGate.Command? {
        keyReason(characters: characters, modifiers: modifiers) == nil
            ? (modifiers == [.command] ? .undo : .redo) : nil
    }

    /// `notZ` or `flagsMismatch` for a key that's neither ⌘Z nor ⇧⌘Z exactly, else `nil`; the cheap first check.
    static func keyReason(characters: String?, modifiers: Modifiers) -> Reason? {
        guard characters?.lowercased() == "z" else {
            return .notZ
        }
        return modifiers == [.command] || modifiers == [.command, .shift] ? nil : .flagsMismatch
    }

    /// The first thing that stops the monitor, or `act` when nothing does: the key is ⌘Z or ⇧⌘Z exactly, in the
    /// app's key window, with no menu tracking, the gate open, the manager able to run it, and its menu item
    /// disabled.
    static func reason(_ input: Input) -> Reason {
        if let key = keyReason(characters: input.characters, modifiers: input.modifiers) {
            return key
        }
        let redo = input.modifiers.contains(.shift)
        let (can, itemEnabled) =
            redo ? (input.canRedo, input.redoItemEnabled) : (input.canUndo, input.undoItemEnabled)
        let stops: [(Bool, Reason)] = [
            (!input.isAppKeyWindow, .notKeyWindow),
            (input.isMenuTracking, .tracking),
            (input.gateClosed, .gateClosed),
            (!can, .cannotRun),
            (itemEnabled == nil, .noItem),
            (itemEnabled == true, .itemEnabled),
        ]
        return stops.first { $0.0 }?.1 ?? .act
    }

    /// Acts only when `reason(_:)` is `act`.
    static func decide(_ input: Input) -> Decision {
        guard reason(input) == .act, let command = command(characters: input.characters, modifiers: input.modifiers)
        else {
            return .pass
        }
        return .act(command)
    }
}

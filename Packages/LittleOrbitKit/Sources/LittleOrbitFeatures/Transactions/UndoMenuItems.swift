import Foundation

/// The Mac Edit menu's Undo and Redo items for the undo manager ⌘Z reaches, titled with the step's name (D288.3,
/// D290.2): "Undo Typing" while a field has its own undo, "Undo Pay Phone Plan" for a window step, and dimmed when
/// there's nothing to undo or redo, or while a batch runs (D407.1, #293).
///
/// Which manager: `UndoRedoCommands` passes the one `NSApp.sendAction(undo:, to: nil, from: nil)` reaches, the key
/// window's first responder's `undoManager` (a field editor's while someone types, which `NSResponder` otherwise
/// takes from its next responder up to the window), else the key window's own. So an item is never dimmed while
/// that manager could undo, nor on when it couldn't. `nil` is no key window, so both are dimmed.
public struct UndoMenuItems: Equatable, Sendable {
    public var undoTitle: String
    public var redoTitle: String
    public var canUndo: Bool
    public var canRedo: Bool

    /// `gateClosed`: whether the batch gate holds Undo and Redo off now (`UndoCommandGate.isClosed`). Then both are
    /// dimmed, and the titles still name the steps, so they're right as soon as the gate opens (D407.2).
    @MainActor
    public init(_ manager: (any UndoRegistrar)?, gateClosed: Bool) {
        let named = { (name: String?) in name.flatMap { $0.isEmpty ? nil : $0 } }
        undoTitle = UndoText.menuUndo(named(manager?.undoActionName))
        redoTitle = UndoText.menuRedo(named(manager?.redoActionName))
        canUndo = !gateClosed && (manager?.canUndo ?? false)
        canRedo = !gateClosed && (manager?.canRedo ?? false)
    }
}

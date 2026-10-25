import Foundation

/// The Mac Edit menu's Undo and Redo items for the undo manager ⌘Z reaches (D285.5): "Undo Typing" while a field
/// has its own undo, "Undo Pay Phone Plan" for a window step, and dimmed when there's nothing to undo or redo.
/// `UndoRedoCommands` builds it from the key window's first responder; `nil` is no window, so both are dimmed.
public struct UndoMenuItems: Equatable, Sendable {
    public var undoTitle: String
    public var redoTitle: String
    public var canUndo: Bool
    public var canRedo: Bool

    @MainActor
    public init(_ manager: (any UndoRegistrar)?) {
        let named = { (name: String?) in name.flatMap { $0.isEmpty ? nil : $0 } }
        undoTitle = UndoText.menuUndo(named(manager?.undoActionName))
        redoTitle = UndoText.menuRedo(named(manager?.redoActionName))
        canUndo = manager?.canUndo ?? false
        canRedo = manager?.canRedo ?? false
    }
}

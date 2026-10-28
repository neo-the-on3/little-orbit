import Foundation
import LittleOrbitCore

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif

// MARK: `ledger.editMenu.action`, each Undo or Redo pressed or sent (#286; Tester2 on #201)

extension UndoCommandGate {
    /// The signpost `ledger.editMenu.action`, tagged `undoSent`, `undoBlocked`, `redoSent` or `redoBlocked`, with, in
    /// order: `NSApp.currentEvent`'s type and timestamp, the outermost and innermost events being dispatched's types,
    /// the dispatched key-down's time, and whether the gate is closed (1 or 0); -1 for each one there's none of, and
    /// -2 as the outer type with no `sendEvent` wrapper.
    ///
    /// Logged once per press or send, from one of two places, never both:
    /// - `perform(_:send:)` refusing Edit › Undo or Redo while the gate is closed (`undoBlocked`, `redoBlocked`).
    ///   It sends nothing then, so the app's `sendAction` guard never sees that press (#201).
    /// - The app's `NSApplication.sendAction(_:to:from:)` guard, for every `undo:` or `redo:` sent, an Edit menu
    ///   press `perform` let through included: `undoSent` or `redoSent`, or blocked when the gate closed some other way.
    static func traceAction(_ command: Command, allowed: Bool) {
        let tag: StaticString =
            switch (command, allowed) {
            case (.undo, true): "undoSent"
            case (.undo, false): "undoBlocked"
            case (.redo, true): "redoSent"
            case (.redo, false): "redoBlocked"
            }
        let dispatch = EventDispatch.shared
        #if canImport(AppKit) && os(macOS)
            let currentEvent = NSApp?.currentEvent
            let event = [currentEvent.map { Double($0.type.rawValue) } ?? -1, currentEvent?.timestamp ?? -1]
        #else
            let event: [Double] = [-1, -1]
        #endif
        BatchTrace.event(
            "ledger.editMenu.action",
            tag,
            values: event + [
                Double(dispatch.outermostType),
                Double(dispatch.innermostType),
                dispatch.current?.time ?? -1,
                shared.isClosed ? 1 : 0,
            ],
        )
    }
}

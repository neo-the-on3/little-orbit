import Foundation
import LittleOrbitCore

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif

/// Edit › Undo and Redo, off while a batch runs (D407 on #286, the Product Manager's ruling through the Tech
/// Architect). From the batch's start to its end, both items are dimmed, for VoiceOver too, and ⌘Z or ⇧⌘Z does
/// nothing but the standard beep (D407.1, D407.3). They come back as the batch ends, titled at once from the window's
/// `UndoManager`, so one Undo reverts the whole batch once (D407.2). Every other command, New Transaction (⌘N) among
/// them, stays as it was (D407.3).
///
/// On the Mac the app's `NSApplication` asks this before it finds a target for an action
/// (`LittleOrbitApplication.target(forAction:to:from:)`): with none, AppKit's own menu validation dims the item, and
/// its key equivalent beeps. The system items are kept rather than replaced with SwiftUI's, so Undo still goes to
/// whatever the responder chain has, a text field's typing in a sheet or Settings included, under the title its
/// `UndoManager` gives. The Edit menu is validated again at the start and the end (`refreshMenu`), so a menu already
/// open dims at the start. A menu still open at the end keeps them off until it closes (`batchEnded()`), so an item
/// pressed during the batch and released after it runs nothing.
///
/// What's left of the D403 drop is only for a ⌘Z that waited in the event queue while the main thread was blocked
/// (`QueuedCommandPolicy`).
@MainActor
final class UndoCommandGate {
    /// The app's: `LedgerUpdates` opens and closes it, and the app's `NSApplication` reads it.
    static let shared = UndoCommandGate()

    /// The two commands the gate holds.
    enum Command: Equatable, Sendable {
        case undo
        case redo
    }

    /// Whether Undo and Redo are off now: from a batch's start until its end, or, when it ends while a menu is open,
    /// until that menu has closed.
    private(set) var isClosed = false
    /// Whether a batch is running now.
    private(set) var isBatchRunning = false
    /// Validates the Edit menu again and signposts its items; tests count it.
    var refreshMenu: @MainActor (_ phase: StaticString) -> Void = UndoCommandGate.refreshEditMenu
    /// Whether a menu, or a control, is tracking the mouse or keyboard now: the main run loop runs in its
    /// event-tracking mode; tests set it.
    var isTracking: @MainActor () -> Bool = UndoCommandGate.mainIsTracking
    /// Runs a block at the next turn of the main run loop in its default mode, which comes only once tracking has
    /// ended; tests run it by hand.
    var nextDefaultModeTurn: @MainActor (@escaping @MainActor () -> Void) -> Void = UndoCommandGate.mainDefaultModeTurn

    /// The command an action's selector name is, as the Edit menu sends it: `undo:` or `redo:`.
    static func command(forAction name: String) -> Command? {
        switch name {
        case "undo:": .undo
        case "redo:": .redo
        default: nil
        }
    }

    /// Whether `command` may run now.
    func allows(_ command: Command) -> Bool {
        !isClosed
    }

    /// Whether the action named `name` may find a target now: Undo and Redo only while the gate is open; anything
    /// else, such as New Transaction, always.
    func allows(action name: String) -> Bool {
        Self.command(forAction: name).map(allows) ?? true
    }

    func batchStarted() {
        isBatchRunning = true
        isClosed = true
        refreshMenu("start")
    }

    /// Opens the gate, or, with a menu open, once it has closed: an item pressed in it during the batch, its
    /// mouse-up or Return handled after the end, then finds Undo still off and runs nothing (D407.2). Reopened, the
    /// menu shows Undo on, titled.
    func batchEnded() {
        isBatchRunning = false
        guard isTracking() else {
            isClosed = false
            refreshMenu("end")
            return
        }
        refreshMenu("endWhileTracking")
        nextDefaultModeTurn { [weak self] in self?.openAfterTracking() }
    }

    private func openAfterTracking() {
        guard !isBatchRunning, isClosed else {
            return
        }
        isClosed = false
        refreshMenu("afterTracking")
    }

    private static func mainIsTracking() -> Bool {
        #if canImport(AppKit) && os(macOS)
            RunLoop.main.currentMode == .eventTracking
        #else
            false
        #endif
    }

    private static func mainDefaultModeTurn(_ block: @escaping @MainActor () -> Void) {
        #if canImport(AppKit) && os(macOS)
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated { block() }
            }
        #else
            _ = block
        #endif
    }

    /// The Edit menu validated again: `NSMenu.update()` on the menu that holds Undo, then the signpost
    /// `ledger.editMenu.state`, tagged with `phase`: `start`, `end`, `endWhileTracking` (a menu was open at the end)
    /// or `afterTracking` (that menu has closed), with, in order: whether Undo is on, whether Redo is (1 or 0, -1 for
    /// no such item), whether the gate is closed, whether Undo's item has a target of its own (1 or 0, -1 for none),
    /// which AppKit's validation would then ask instead of the responder chain, and whether the main run loop is in
    /// its event-tracking mode (1 or 0).
    private static func refreshEditMenu(_ phase: StaticString) {
        #if canImport(AppKit) && os(macOS)
            let undo = item(sending: "undo:")
            let redo = item(sending: "redo:")
            undo?.menu?.update()
            if redo?.menu !== undo?.menu {
                redo?.menu?.update()
            }
            let state = { (item: NSMenuItem?) in item.map { $0.isEnabled ? 1.0 : 0 } ?? -1 }
            BatchTrace.event(
                "ledger.editMenu.state",
                phase,
                values: [
                    state(undo),
                    state(redo),
                    shared.isClosed ? 1 : 0,
                    undo.map { $0.target == nil ? 0.0 : 1.0 } ?? -1,
                    mainIsTracking() ? 1 : 0,
                ],
            )
        #else
            _ = phase
        #endif
    }

    #if canImport(AppKit) && os(macOS)
        /// The main menu's item that sends `action`, in any submenu.
        private static func item(sending action: String) -> NSMenuItem? {
            func find(in menu: NSMenu) -> NSMenuItem? {
                for item in menu.items {
                    if let sent = item.action, NSStringFromSelector(sent) == action {
                        return item
                    }
                    if let submenu = item.submenu, let found = find(in: submenu) {
                        return found
                    }
                }
                return nil
            }
            return NSApp?.mainMenu.flatMap(find)
        }
    #endif
}

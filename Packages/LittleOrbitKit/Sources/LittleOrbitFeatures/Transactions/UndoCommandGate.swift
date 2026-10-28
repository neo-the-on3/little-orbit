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
/// On the Mac, Edit › Undo and Redo are the app's own SwiftUI items (`UndoRedoCommands`, #201), which replace the
/// system ones so they can name the step. Each is drawn from `UndoMenuItems(_:gateClosed:)`, so it's dimmed while the
/// gate is closed, and pressed, it runs only through `perform(_:send:)`, which sends nothing while closed (D403.1).
/// What it sends is the standard `undo:` or `redo:` down the responder chain (`NSApp.sendAction`), so Undo still goes
/// to whatever has focus, a text field's typing in a sheet or Settings included (D407.6), and the app's
/// `NSApplication` still refuses it while closed (`LittleOrbitApplication.sendAction(_:to:from:)`). At the start and
/// the end, the gate has the items read again at once (`refreshMenu`, through `editMenuObserver`), so their titles and
/// enabled state follow in the same turn (D407.2). A menu still open at the end keeps them off until it closes
/// (`batchEnded()`), so an item pressed during the batch and released after it runs nothing.
///
/// What's left of the D403 drop is only for a ⌘Z that waited in the event queue while the main thread was blocked
/// (`QueuedCommandPolicy`).
@MainActor
final class UndoCommandGate {
    /// The app's: `LedgerUpdates` opens and closes it, and the app's `NSApplication` reads it. It follows every menu
    /// that starts tracking on the Mac (`observeMenuTracking()`, m14).
    static let shared: UndoCommandGate = {
        let gate = UndoCommandGate()
        gate.observeMenuTracking()
        return gate
    }()

    /// The two commands the gate holds.
    enum Command: Equatable, Sendable, CaseIterable {
        case undo
        case redo

        /// Its action's selector name, as the Edit menu sends it.
        var actionName: String {
            switch self {
            case .undo: "undo:"
            case .redo: "redo:"
            }
        }

        #if canImport(AppKit) && os(macOS)
            /// Its action, `undo:` or `redo:`, which `NSResponder`s answer down the responder chain.
            var action: Selector { Selector(actionName) }
        #endif
    }

    /// Whether Undo and Redo are off now: from a batch's start until its end, or, when it ends while a menu is open,
    /// until that menu has closed.
    private(set) var isClosed = false
    /// Whether a batch is running now.
    private(set) var isBatchRunning = false
    /// When the batch running now started, and when the last one ran, on the `systemUptime` clock (m14).
    private(set) var batchStart: TimeInterval?
    private(set) var lastBatch: ClosedRange<TimeInterval>?
    /// Whether a menu that started tracking holds Undo and Redo off until it closes (m14).
    private(set) var isHeldByMenu = false
    /// The `systemUptime` clock, and seconds since the left mouse button last went down (the Mac's event source,
    /// `nil` elsewhere); tests set them (m14).
    var uptime: @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var secondsSinceLeftMouseDown: @MainActor () -> Double? = UndoCommandGate.eventSourceSecondsSinceLeftMouseDown
    /// Whether `refreshEditMenu` is reading the Edit menu's items again now, for `ledger.editMenu.validate`.
    private(set) var isRefreshing = false
    /// Reads Edit › Undo and Redo again for whether the gate is closed now, and returns them as they'll show: set by
    /// the Mac app's Edit menu (`UndoRedoCommands`), `nil` elsewhere; tests stub it. It keeps the gate free of any
    /// view: the menu observes the gate, never the other way round.
    var editMenuObserver: (@MainActor (_ gateClosed: Bool) -> UndoMenuItems)?
    /// Keeps the menu-tracking observation for the app's life.
    var menuTrackingObservation: (any NSObjectProtocol)?
    /// Reads the Edit menu's items again and signposts them (`refreshEditMenu`); tests count it.
    var refreshMenu: @MainActor (_ phase: StaticString) -> Void = { _ in }
    /// Whether a menu, or a control, is tracking the mouse or keyboard now: the main run loop runs in its
    /// event-tracking mode; tests set it.
    var isTracking: @MainActor () -> Bool = UndoCommandGate.mainIsTracking
    /// Runs a block at the next turn of the main run loop in its default mode, which comes only once tracking has
    /// ended; tests run it by hand.
    var nextDefaultModeTurn: @MainActor (@escaping @MainActor () -> Void) -> Void = UndoCommandGate.mainDefaultModeTurn

    init() {
        refreshMenu = { [weak self] phase in self?.refreshEditMenu(phase) }
    }

    /// The command an action's selector name is, as the Edit menu sends it: `undo:` or `redo:`.
    static func command(forAction name: String) -> Command? {
        Command.allCases.first { $0.actionName == name }
    }

    /// Edit › Undo or Redo pressed, by a click, its key equivalent, VoiceOver or Voice Control (D403.1): while the
    /// gate is closed it returns false and never calls `send`, and nothing is kept to run later, so the batch's end
    /// runs nothing. While open, `send` runs once, with the command; the Mac app's sends its action down the
    /// responder chain, `NSApp.sendAction(command.action, to: nil, from: nil)` (D407.6). Returns what `send` did.
    ///
    /// It checks only whether the gate is closed. A ⌘Z pressed during the batch but delivered after its end finds
    /// the gate open; the window's Undo then drops it by its key-down's time (`LedgerUpdates.dropsQueuedCommand`,
    /// D403), which `NSApp.sendAction` reaches inside that key-down's dispatch.
    @discardableResult
    func perform(_ command: Command, send: (Command) -> Bool) -> Bool {
        guard allows(command) else {
            return false
        }
        return send(command)
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

    func batchStarted(at start: TimeInterval) {
        isBatchRunning = true
        batchStart = start
        isClosed = true
        refreshMenu(isTracking() ? "startWhileTracking" : "start")
    }

    /// Opens the gate, or, with a menu open, once it has closed: an item pressed in it during the batch, its
    /// mouse-up or Return handled after the end, then finds Undo still off and runs nothing (D407.2). Reopened, the
    /// menu shows Undo on, titled.
    func batchEnded(at end: TimeInterval) {
        isBatchRunning = false
        lastBatch = min(batchStart ?? end, end)...end
        batchStart = nil
        guard isTracking() || isHeldByMenu else {
            isClosed = false
            refreshMenu("end")
            return
        }
        refreshMenu("endWhileTracking")
        nextDefaultModeTurn { [weak self] in self?.openAfterTracking() }
    }

    /// Closes the gate for a menu that's tracking (m14).
    func holdForMenu() {
        isHeldByMenu = true
        isClosed = true
    }

    /// Opens the gate once the menu that held it has closed, unless a batch runs again.
    func openAfterTracking() {
        isHeldByMenu = false
        guard !isBatchRunning, isClosed else {
            return
        }
        isClosed = false
        refreshMenu("afterTracking")
    }

    static func mainIsTracking() -> Bool {
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

    /// The Edit menu's Undo and Redo read again for the gate now, through `editMenuObserver`, then the signpost
    /// `ledger.editMenu.state`, tagged with `phase`: `start` (`startWhileTracking` with a menu open), `end`,
    /// `endWhileTracking` (a menu was open at the end), `afterTracking` (that menu has closed) or `heldByMenu` (m14).
    ///
    /// Its values, in order, since #201 (Undo and Redo are the app's SwiftUI items, `UndoMenuItems`): whether Undo is
    /// on, whether Redo is (1 or 0, -1 with no Edit menu observing), whether the gate is closed (1 or 0), whether the
    /// main run loop is in its event-tracking mode (1 or 0), and whether Undo's title names a step, as "Undo Pay Gym"
    /// does, and Redo's (1 or 0, -1 with no Edit menu observing).
    ///
    /// Before #201 (#286, D408), with the system items found by their `undo:` action: Undo's and Redo's
    /// `NSMenuItem.isEnabled` after `NSMenu.update()` (1 or 0, -1 for no such item), whether the gate is closed,
    /// whether Undo's item had a target of its own (1 or 0, -1 for none), whether the main run loop was in its
    /// event-tracking mode, and Undo's item's identity (`itemID`, -1 for none).
    func refreshEditMenu(_ phase: StaticString) {
        isRefreshing = true
        let items = editMenuObserver?(isClosed)
        isRefreshing = false
        let flag = { (isOn: Bool?) in isOn.map { $0 ? 1.0 : 0 } ?? -1 }
        BatchTrace.event(
            "ledger.editMenu.state",
            phase,
            values: [
                flag(items?.canUndo),
                flag(items?.canRedo),
                isClosed ? 1 : 0,
                isTracking() ? 1 : 0,
                flag(items.map { $0.undoTitle != UndoText.menuUndo(nil) }),
                flag(items.map { $0.redoTitle != UndoText.menuRedo(nil) }),
            ],
        )
    }

    #if canImport(AppKit) && os(macOS)
        /// A short number for which `NSMenuItem` an item is, for the `ledger.editMenu.validate` signpost: a new one
        /// means SwiftUI or AppKit swapped it in.
        static func itemID(_ item: NSMenuItem) -> Double {
            Double(UInt(bitPattern: ObjectIdentifier(item).hashValue) % 1_000_000)
        }
    #endif
}

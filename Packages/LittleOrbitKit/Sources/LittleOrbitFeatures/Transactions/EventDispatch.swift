import Foundation
import LittleOrbitCore

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif
#if canImport(OSLog)
    import OSLog
#endif

/// The events AppKit is dispatching right now, outermost first (Tech Architect's B5 on bab2ad8), so an Undo or Redo
/// can tell a queued ⌘Z from anything else (`QueuedCommandPolicy`). Each one is added as
/// `NSApplication.sendEvent(_:)` starts and taken off as it returns (`LittleOrbitApplication`). A key equivalent is
/// matched inside its key-down's dispatch, so a command it sends sees that key-down here. A menu item chosen with the
/// mouse or keyboard is sent from the menu's own tracking loop, outside `sendEvent` (Tester2 on 4839e5d), and an
/// Accessibility action (VoiceOver, Voice Control, an AXPress) outside any dispatch: they see none, and Edit › Undo
/// and Redo are off during a batch for them instead (`UndoCommandGate`, D407). The Mac app's entry point makes the
/// subclass the shared app before SwiftUI starts (`LittleOrbitApplication.makeShared()`), and reports at launch
/// whether it took (`reportSource(live:)`); the first queued-command check makes sure again (`checkWiringOnce()`).
///
/// A sendEvent override rather than a local event monitor: a monitor sees an event as it arrives, but not when its
/// dispatch ends, so it can't tell a command sent while handling that event from one sent after it.
///
/// Nothing here depends on a pop that can be skipped (Tech Architect's m11 on 4ea9bd6). An Objective-C exception
/// unwinding through `sendEvent` skips its `defer`, and AppKit's run loop catches it and carries on; a leftover
/// left-mouse entry would make a later Accessibility command look mouse-driven. So each dispatch, as it ends, takes
/// off everything above its own depth, which repairs a skipped pop nested inside it; and each one asks for a clear at
/// the next turn of the main run loop in its default mode, which comes only once no dispatch is running (menu and
/// control tracking turn it in the event-tracking mode instead), and repairs one skipped at the outermost level.
@MainActor
final class EventDispatch {
    /// The app's, which `LittleOrbitApplication` fills in.
    static let shared = EventDispatch()

    /// One event being dispatched: its `NSEvent.EventType` raw value, and the key-down, if it's one.
    struct Entry: Equatable {
        var type: Int
        var input: QueuedCommandPolicy.Event?
    }

    /// Outermost first.
    private(set) var entries: [Entry] = []
    /// Whether the app's `sendEvent` wrapper is in place: without it nothing is ever being dispatched, so no command
    /// drops, and `ledger.command.dispatch` reads -2. The launch self-check says so loudly (`reportSource(live:)`).
    private(set) var isInstalled = false
    /// Runs a block at the next turn of the main run loop in its default mode; tests run it by hand.
    var nextTopLevelTurn: @MainActor (@escaping @MainActor () -> Void) -> Void = EventDispatch.mainDefaultModeTurn
    /// Whether a clear is already asked for.
    private var clearAsked = false
    /// Whether the first queued-command check has checked the app's `NSApplication` (m12).
    private(set) var wiringChecked = false
    /// What a check that finds the subclass missing stops with: a Debug build's assertion; tests record it.
    var wiringFailed: @MainActor (String) -> Void = { assertionFailure($0) }

    /// The launch self-check: whether the app's `NSApplication` is the one that records its dispatches. Signposted
    /// once, as `ledger.command.dispatchSource` tagged `live` or `absent`, and logged (`app.littleorbit`, `Batch`).
    /// Absent leaves it uninstalled: no command drops, and each check's outer type reads -2. The Mac app also stops a
    /// Debug build there (`LittleOrbitApplication.makeShared()`).
    func reportSource(live: Bool) {
        if live {
            isInstalled = true
        }
        BatchTrace.event("ledger.command.dispatchSource", live ? "live" : "absent")
        #if canImport(OSLog)
            let log = Logger(subsystem: "app.littleorbit", category: "Batch")
            if live {
                log.notice("ledger.command.dispatchSource live")
            } else {
                log.fault("ledger.command.dispatchSource absent: queued Undo and Redo are never dropped (D403)")
            }
        #endif
    }

    /// The check that always runs, whatever the entry point did (Tech Architect's m12 on 4839e5d): on the first
    /// queued-command decision, whether `NSApp` is a `LittleOrbitApplication`. Signposted once as
    /// `ledger.command.dispatchWiring`, tagged `live` or `absent`; absent is also logged as a fault and stops a
    /// Debug build. Nothing with no app at all, as under `swift test`, and nothing off the Mac.
    func checkWiringOnce() {
        #if canImport(AppKit) && os(macOS)
            guard !wiringChecked, let app = NSApp else {
                return
            }
            checkWiring(appIsSubclass: app is LittleOrbitApplication)
        #endif
    }

    /// `checkWiringOnce()` for an app that is, or isn't, the subclass: only the first call checks.
    func checkWiring(appIsSubclass: Bool) {
        guard !wiringChecked else {
            return
        }
        wiringChecked = true
        BatchTrace.event("ledger.command.dispatchWiring", appIsSubclass ? "live" : "absent")
        guard !appIsSubclass else {
            return
        }
        let message =
            "ledger.command.dispatchWiring absent: NSApp isn't LittleOrbitApplication, so a queued ⌘Z is "
            + "never dropped and Edit › Undo stays on during a batch (D407)"
        #if canImport(OSLog)
            Logger(subsystem: "app.littleorbit", category: "Batch").fault("\(message, privacy: .public)")
        #endif
        wiringFailed(message)
    }

    /// `body`, with `entry` being dispatched until it returns, nested inside any already being dispatched.
    func dispatching<T>(_ entry: Entry, _ body: () -> T) -> T {
        let depth = enter(entry)
        defer { leave(depth) }
        return body()
    }

    /// Adds `entry` and returns the depth to end it at, `leave(_:)`. Split from `dispatching` only so a test can skip
    /// the end, as an exception would.
    func enter(_ entry: Entry) -> Int {
        let depth = entries.count
        entries.append(entry)
        if !clearAsked {
            clearAsked = true
            nextTopLevelTurn { [weak self] in self?.clearAtTopLevel() }
        }
        return depth
    }

    /// Ends the dispatch that `enter(_:)` returned `depth` for, and any left above it by a skipped end.
    func leave(_ depth: Int) {
        if entries.count > depth {
            entries.removeSubrange(depth...)
        }
    }

    /// No dispatch runs at a default-mode turn of the main run loop: anything left is from a skipped end.
    /// Signposted as `ledger.command.dispatchCleared` with how many, when there were any.
    private func clearAtTopLevel() {
        clearAsked = false
        guard !entries.isEmpty else {
            return
        }
        BatchTrace.event("ledger.command.dispatchCleared", value: Double(entries.count))
        entries.removeAll()
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

    /// The innermost key-down being dispatched: what a command running now was driven by. An event of another kind
    /// dispatched inside it, such as an app-defined one, doesn't hide it. `nil` when none is, as for a menu or an
    /// Accessibility action.
    var current: QueuedCommandPolicy.Event? {
        entries.last { $0.input != nil }?.input
    }

    /// The outermost event being dispatched, of any kind, as its raw type; -1 for none, -2 with no wrapper. For the
    /// signposts only.
    var outermostType: Int {
        guard isInstalled else {
            return -2
        }
        return entries.first?.type ?? -1
    }

    /// The innermost event being dispatched, of any kind, as its raw type; -1 for none. For the signposts only.
    var innermostType: Int {
        entries.last?.type ?? -1
    }
}

#if canImport(AppKit) && os(macOS)
    /// The app's `NSApplication`: it records each event it dispatches in `EventDispatch.shared` for as long as
    /// `sendEvent(_:)` runs (B5 on bab2ad8), and holds Edit › Undo and Redo off while a batch runs (D407,
    /// `UndoCommandGate`). The `@objc` name is the one `NSPrincipalClass` gives.
    @objc(LittleOrbitApplication)
    public final class LittleOrbitApplication: NSApplication {
        /// Makes this class the app's `NSApplication`, as AppKit documents for a subclass: `shared` sent to it before
        /// anything else creates the app object, and every later `NSApplication.shared`, SwiftUI's included, returns
        /// that one. Call it first in `main()`, before `App.main()`. Then checks that `NSApp` is this class and says so
        /// (`EventDispatch.reportSource(live:)`); a Debug build stops if it isn't.
        public static func makeShared() {
            let app = shared
            let live = app is LittleOrbitApplication && NSApp === app
            EventDispatch.shared.reportSource(live: live)
            if !live {
                assertionFailure("NSApp is \(type(of: app)), not LittleOrbitApplication: queued Undo/Redo won't drop")
            }
        }

        override public func sendEvent(_ event: NSEvent) {
            let entry = EventDispatch.Entry(
                type: Int(event.type.rawValue),
                input: QueuedCommandPolicy.event(for: event),
            )
            EventDispatch.shared.dispatching(entry) {
                super.sendEvent(event)
            }
        }

        /// No target for Undo or Redo while a batch runs: AppKit's menu validation then dims the item, for VoiceOver
        /// too, and its key equivalent beeps (D407.1). Every other action, and these once the batch ends, as AppKit
        /// finds it.
        override public func target(forAction action: Selector, to target: Any?, from sender: Any?) -> Any? {
            let name = NSStringFromSelector(action)
            let gate = UndoCommandGate.shared
            let watched = gate.isClosed || UndoCommandGate.mainIsTracking()
            if watched, let command = UndoCommandGate.command(forAction: name) {
                traceValidation(command, sender: sender)
            }
            guard gate.allows(action: name) else {
                return nil
            }
            return super.target(forAction: action, to: target, from: sender)
        }

        /// The signpost `ledger.editMenu.validate`, for each lookup of Undo's or Redo's target while the gate is
        /// closed or a menu is tracking, as AppKit's validation, or anything else, asks: tagged `undo` or `redo`, with,
        /// in order: whether the gate is closed, whether a menu is tracking, whether the sender is a menu item, its
        /// enabled state and whether its title is the bare "Undo" or "Redo" (1 or 0, -1 for no menu item), whether
        /// it's the gate's own refresh asking (1 or 0), and the item's identity (`UndoCommandGate.itemID`, -1 for
        /// none). Tester2's 2b on e291012: a validation of the open menu that never shows here went another way.
        private func traceValidation(_ command: UndoCommandGate.Command, sender: Any?) {
            let item = sender as? NSMenuItem
            let bare = command == .undo ? "Undo" : "Redo"
            BatchTrace.event(
                "ledger.editMenu.validate",
                command == .undo ? "undo" : "redo",
                values: [
                    UndoCommandGate.shared.isClosed ? 1 : 0,
                    UndoCommandGate.mainIsTracking() ? 1 : 0,
                    item == nil ? 0 : 1,
                    item.map { $0.isEnabled ? 1.0 : 0 } ?? -1,
                    item.map { $0.title == bare ? 1.0 : 0 } ?? -1,
                    UndoCommandGate.shared.isRefreshing ? 1 : 0,
                    item.map(UndoCommandGate.itemID) ?? -1,
                ],
            )
        }

        /// Undo and Redo sent while a batch runs do nothing, however they got past validation. Each one sent is
        /// signposted as `ledger.editMenu.action` (`traceAction`).
        override public func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
            let name = NSStringFromSelector(action)
            guard let command = UndoCommandGate.command(forAction: name) else {
                return super.sendAction(action, to: target, from: sender)
            }
            let allowed = UndoCommandGate.shared.allows(command)
            traceAction(command, allowed: allowed)
            return allowed && super.sendAction(action, to: target, from: sender)
        }

        /// The signpost `ledger.editMenu.action`, tagged `undoSent`, `undoBlocked`, `redoSent` or `redoBlocked`,
        /// with, in order: `NSApp.currentEvent`'s type and timestamp, the outermost and innermost events being
        /// dispatched's types, the dispatched key-down's time, and whether the gate is closed (1 or 0); -1 for each
        /// one there's none of, and -2 as the outer type with no `sendEvent` wrapper.
        private func traceAction(_ command: UndoCommandGate.Command, allowed: Bool) {
            let tag: StaticString =
                switch (command, allowed) {
                case (.undo, true): "undoSent"
                case (.undo, false): "undoBlocked"
                case (.redo, true): "redoSent"
                case (.redo, false): "redoBlocked"
                }
            let dispatch = EventDispatch.shared
            BatchTrace.event(
                "ledger.editMenu.action",
                tag,
                values: [
                    currentEvent.map { Double($0.type.rawValue) } ?? -1,
                    currentEvent?.timestamp ?? -1,
                    Double(dispatch.outermostType),
                    Double(dispatch.innermostType),
                    dispatch.current?.time ?? -1,
                    UndoCommandGate.shared.isClosed ? 1 : 0,
                ],
            )
        }
    }
#endif

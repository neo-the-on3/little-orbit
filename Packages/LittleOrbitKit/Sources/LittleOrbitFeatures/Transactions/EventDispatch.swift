import Foundation
import LittleOrbitCore

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif
#if canImport(OSLog)
    import OSLog
#endif

/// The events AppKit is dispatching right now, outermost first (Tech Architect's B5 on bab2ad8), so an Undo or Redo
/// can tell what drove it (`QueuedCommandPolicy`). Each one is added as `NSApplication.sendEvent(_:)` starts and taken
/// off as it returns (`LittleOrbitApplication`). A menu's tracking and a key equivalent run nested inside the dispatch
/// of the mouse-down or key-down that started them, so a command they send sees that event here. An Accessibility
/// action (VoiceOver, Voice Control, an AXPress) arrives outside any dispatch, and sees none. The Mac app's entry point
/// makes the subclass the shared app before SwiftUI starts (`LittleOrbitApplication.makeShared()`), and reports at
/// launch whether it took (`reportSource(live:)`).
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

    /// One event being dispatched: its `NSEvent.EventType` raw value, and the input event, if it's a mouse button's
    /// or the keyboard's.
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

    /// The innermost input event being dispatched: what a command running now was driven by. An event of another
    /// kind dispatched inside it, such as an app-defined one, doesn't hide it. `nil` when none is, as for an
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
}

#if canImport(AppKit) && os(macOS)
    /// The app's `NSApplication`: it records each event it dispatches in `EventDispatch.shared` for as long as
    /// `sendEvent(_:)` runs (B5 on bab2ad8). The `@objc` name is the one `NSPrincipalClass` gives.
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
    }
#endif

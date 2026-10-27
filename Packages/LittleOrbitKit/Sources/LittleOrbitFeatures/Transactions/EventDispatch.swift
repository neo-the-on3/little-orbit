import Foundation

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif

/// The events AppKit is dispatching right now, outermost first (Tech Architect's B5 on bab2ad8), so an Undo or Redo
/// can tell what drove it (`QueuedCommandPolicy`). Each one is added as `NSApplication.sendEvent(_:)` starts and taken
/// off as it returns (`LittleOrbitApplication`). A menu's tracking and a key equivalent run nested inside the dispatch
/// of the mouse-down or key-down that started them, so a command they send sees that event here. An Accessibility
/// action (VoiceOver, Voice Control, an AXPress) arrives outside any dispatch, and sees none.
///
/// A sendEvent override rather than a local event monitor: a monitor sees an event as it arrives, but not when its
/// dispatch ends, so it can't tell a command sent while handling that event from one sent after it.
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
    /// drops (fail open), and `ledger.command.dispatch` reads -2 so a log shows it.
    private(set) var isInstalled = false

    func installed() {
        isInstalled = true
    }

    /// `body`, with `entry` being dispatched until it returns, nested inside any already being dispatched.
    func dispatching<T>(_ entry: Entry, _ body: () -> T) -> T {
        entries.append(entry)
        defer { entries.removeLast() }
        return body()
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
    /// The app's `NSApplication`, named by `NSPrincipalClass` in the Mac app's Info.plist: it records each event it
    /// dispatches in `EventDispatch.shared` for as long as `sendEvent(_:)` runs (B5 on bab2ad8).
    @objc(LittleOrbitApplication)
    public final class LittleOrbitApplication: NSApplication {
        override public func finishLaunching() {
            EventDispatch.shared.installed()
            super.finishLaunching()
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

import Foundation

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif

/// Whether an Undo or Redo was asked for while the last batch ran (#285, D398, D403, Tester2's N5 at c8c6594,
/// comment 6440723910; Tech Architect's reviews 5666694381 and 5670733886, the press-time ruling on 3dc318b, and B5 on
/// bab2ad8).
///
/// While a batch saves, or the windows refresh after it, the main thread is blocked, so a click in an Edit menu left
/// open, or a ⌘Z, waits in the event queue. It's handled once the batch has ended and the busy flag is off, and would
/// undo one step more. So such a command is dropped. What decides is what AppKit is dispatching as the command runs
/// (`EventDispatch`), never how old `NSApp.currentEvent` is:
///
/// - Nothing being dispatched: the command came from Accessibility (VoiceOver, Voice Control, an AXPress), or
///   anything else not driven by an input event. It never drops, whatever event came last (B4 on 0d676f8).
/// - A key event, or any event but the left mouse button's: drops when that event's own time falls inside the last
///   batch, `batch.start ≤ time ≤ batch.end`. An event drops at most one command.
/// - The left mouse button, as a menu item chosen with a click: drops when the latest physical input, the left
///   button's last press or the last key-down, whichever came later, fell inside the batch,
///   `batch.start ≤ input ≤ batch.end`, however late its mouse-up is handled and whichever mouse event is being
///   dispatched. A menu's tracking runs inside the dispatch of the mouse-down that opened it, which may be from before
///   the batch (Tester2 on bab2ad8, B5), so that event's time says nothing about when the item was chosen. The item
///   may be chosen with the keyboard too, arrow keys and Return, so the last key-down counts as well (Tech
///   Architect's edge (b) on 4ea9bd6). An input after the end goes through, however soon. An input drops at most one
///   command.
/// - A VoiceOver choice in a menu opened with a click runs inside that click's dispatch too, and goes by the same
///   rule: VoiceOver's own keys are key-downs, so a choice made after the end goes through. It drops only when the
///   latest input was inside the batch, which can't be told apart from a press inside the batch released after the
///   end, and D403.1 drops that (edge (a), accepted on 4ea9bd6). A menu opened by VoiceOver runs outside any dispatch.
/// - The right and other buttons count as the keyboard does, by their own event's time (Tech Architect's m9 on
///   0d676f8): the press time is only the left button's, so another button's command, such as a context menu's,
///   never borrows a left press from inside the batch.
///
/// `pressTime` is `systemUptime − CGEventSource.secondsSinceLastEventType(.combinedSessionState, .leftMouseDown)`:
/// when the left button last went down, and `keyTime` the same for `.keyDown`. A menu's tracking loop may never pass
/// its mouse-down or key-downs to the app, so the event source is asked instead of the app's events.
///
/// Every time here is seconds since the system started, on one clock: `NSEvent.timestamp`,
/// `ProcessInfo.systemUptime`, which `LedgerUpdates` stamps the batch's start and end with, and so `pressTime`.
enum QueuedCommandPolicy {
    /// The input event a command is handled with: when it happened, and whether it's the left mouse button's.
    struct Event: Equatable, Sendable {
        var time: TimeInterval
        var isMouse = false
        /// The `NSEvent.EventType` raw value, for the signposts only; -1 when unknown.
        var type = -1
    }

    /// How far apart two readings of one press can be, from the event source's clock and `systemUptime` being read
    /// a moment apart: within it, it's the same press.
    static let pressTolerance: TimeInterval = 0.01

    /// When the left mouse button last went down, from `now` and the event source's seconds since then. `nil`, so
    /// no command is dropped for its press, when the reading can't be right: not a number, zero or less (no press
    /// yet, or a source with no permission), or putting the press before the app started (`launch`) or after `now`
    /// (Tech Architect's condition 3: fail open).
    static func pressTime(now: TimeInterval, secondsSince: Double?, launch: TimeInterval) -> TimeInterval? {
        guard let secondsSince, secondsSince.isFinite, secondsSince > 0 else {
            return nil
        }
        let press = now - secondsSince
        guard press >= launch, press <= now else {
            return nil
        }
        return press
    }

    /// Whether to drop the command, for the input event being dispatched as it runs. A left mouse event drops when
    /// the press (`pressTime`) fell inside the last batch and that press hasn't dropped a command already, whenever
    /// the event itself happened (B5). Any other event drops when its own time fell inside the batch and it hasn't
    /// dropped one already. With no event being dispatched, no batch yet, or a mouse event and no press time, it
    /// goes through.
    static func dropsCommand(
        event: Event?,
        pressTime: TimeInterval?,
        keyTime: TimeInterval? = nil,
        lastBatch: ClosedRange<TimeInterval>?,
        lastDroppedEventTime: TimeInterval?,
        lastDroppedPressTime: TimeInterval?,
    ) -> Bool {
        guard let event, let lastBatch else {
            return false
        }
        guard event.isMouse else {
            return lastBatch.contains(event.time) && event.time != lastDroppedEventTime
        }
        guard let input = latestInput(pressTime: pressTime, keyTime: keyTime), lastBatch.contains(input) else {
            return false
        }
        if let lastDroppedPressTime, abs(input - lastDroppedPressTime) <= pressTolerance {
            return false
        }
        return true
    }

    /// The latest physical input a left mouse event's command goes by: the last left press or the last key-down,
    /// whichever came later; either may be unknown (edge (b) on 4ea9bd6).
    static func latestInput(pressTime: TimeInterval?, keyTime: TimeInterval?) -> TimeInterval? {
        guard let pressTime else {
            return keyTime
        }
        guard let keyTime else {
            return pressTime
        }
        return max(pressTime, keyTime)
    }

    /// `dropsCommand(event:pressTime:lastBatch:lastDroppedEventTime:lastDroppedPressTime:)` for an event that isn't
    /// the mouse's.
    static func dropsCommand(
        eventTime: TimeInterval?,
        lastBatch: ClosedRange<TimeInterval>?,
        lastDroppedEventTime: TimeInterval?,
    ) -> Bool {
        dropsCommand(
            event: eventTime.map { Event(time: $0) },
            pressTime: nil,
            lastBatch: lastBatch,
            lastDroppedEventTime: lastDroppedEventTime,
            lastDroppedPressTime: nil,
        )
    }

    /// What drove an event, for whether its command goes by the press time.
    enum Source: Equatable, Sendable {
        /// The left mouse button: the press time's.
        case leftMouse
        /// The right or another mouse button: the press time isn't theirs (m9).
        case otherMouseButton
        /// The keyboard, or anything else.
        case other
    }

    /// The event for a time and what drove it: only the left button's goes by the press time; any other, the right
    /// and other mouse buttons included, by its own time (m9).
    static func event(at time: TimeInterval, from source: Source) -> Event {
        Event(time: time, isMouse: source == .leftMouse)
    }

    #if canImport(AppKit) && os(macOS)
        /// The input event for an event AppKit dispatches, on the `systemUptime` clock: a mouse button's or the
        /// keyboard's. `nil` for any other kind, which drives no command of its own.
        @MainActor
        static func event(for event: NSEvent) -> Event? {
            let source: Source
            switch event.type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
                source = .leftMouse
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp,
                .otherMouseDragged:
                source = .otherMouseButton
            case .keyDown, .keyUp, .flagsChanged:
                source = .other
            default:
                return nil
            }
            var input = Self.event(at: event.timestamp, from: source)
            input.type = Int(event.type.rawValue)
            return input
        }
    #endif

    /// Seconds since the left mouse button last went down anywhere in the login session: the Mac's event source,
    /// `nil` elsewhere, where there's no mouse.
    ///
    /// Session-wide, so a press in another app counts too (condition 2). That's acceptable: a command is dropped for
    /// a press only while one of our left mouse events is being dispatched, and then at most once per press. A press
    /// elsewhere inside the batch, followed by a click of ours on Undo after it, is a newer press, after the end, and
    /// goes through.
    @MainActor
    static func secondsSinceLeftMouseDown() -> Double? {
        #if canImport(AppKit) && os(macOS)
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        #else
            nil
        #endif
    }

    /// Seconds since a key last went down anywhere in the login session, from the same event source and so on the
    /// same clock as the press: `nil` off the Mac. Session-wide too, and read only while one of our left mouse events
    /// is being dispatched.
    @MainActor
    static func secondsSinceKeyDown() -> Double? {
        #if canImport(AppKit) && os(macOS)
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        #else
            nil
        #endif
    }
}

import Foundation

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif

/// Whether an Undo or Redo was asked for while the last batch ran (#285, D398, D403, Tester2's N5 at c8c6594,
/// comment 6440723910; Tech Architect's reviews 5666694381 and 5670733886, and the press-time ruling on 3dc318b).
///
/// While a batch saves, or the windows refresh after it, the main thread is blocked, so a click in an Edit menu left
/// open, or a ⌘Z, waits in the event queue. It's handled once the batch has ended and the busy flag is off, and would
/// undo one step more. So such a command is dropped:
///
/// - From the keyboard, or any event that isn't the mouse's: when its event's time falls inside the last batch,
///   `batch.start ≤ time ≤ batch.end`. An event drops at most one command.
/// - From the mouse, a menu item chosen with a click: when the press that chose it fell inside the batch,
///   `batch.start ≤ pressTime ≤ batch.end`, however late its mouse-up is handled (Tester2 on 3dc318b: pressed just
///   before the end, released after it, and it ran). A press after the end goes through, however soon. A press drops
///   at most one command.
///
/// `pressTime` is `systemUptime − CGEventSource.secondsSinceLastEventType(.combinedSessionState, .leftMouseDown)`:
/// when the left button last went down. A menu's tracking loop may never pass its mouse-down to the app, so the
/// event source is asked instead of the app's events.
///
/// Every time here is seconds since the system started, on one clock: `NSEvent.timestamp`,
/// `ProcessInfo.systemUptime`, which `LedgerUpdates` stamps the batch's start and end with, and so `pressTime`.
///
/// AppKit never clears `NSApp.currentEvent`, so a command not driven by an event of its own (VoiceOver, Voice
/// Control or any other Accessibility press) sees whatever event came last. Only an event newer than the one the last
/// command was handled with counts (`fresh(_:after:)`); a stale one counts as no event, and no event never drops.
/// One from before the batch isn't inside it either, so the command goes through.
enum QueuedCommandPolicy {
    /// The event a command is handled with: when it happened, and whether it's the mouse's.
    struct Event: Equatable, Sendable {
        var time: TimeInterval
        var isMouse = false
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

    /// The event, if it's newer than the one the last command was handled with (`last`); otherwise `nil`, as for a
    /// command with no event: the stale event an Accessibility press sees (condition 1).
    static func fresh(_ event: Event?, after last: TimeInterval?) -> Event? {
        guard let event else {
            return nil
        }
        guard let last else {
            return event
        }
        return event.time > last ? event : nil
    }

    /// Whether to drop the command, for its fresh event. A mouse event drops when the press (`pressTime`) fell inside
    /// the last batch, the event came with or after it, and that press hasn't dropped a command already. Any other
    /// event drops when its own time fell inside the batch and it hasn't dropped one already. With no event, no
    /// batch yet, or a mouse event and no press time, it goes through.
    static func dropsCommand(
        event: Event?,
        pressTime: TimeInterval?,
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
        guard let pressTime, lastBatch.contains(pressTime), event.time >= pressTime - pressTolerance else {
            return false
        }
        if let lastDroppedPressTime, abs(pressTime - lastDroppedPressTime) <= pressTolerance {
            return false
        }
        return true
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

    /// The event being handled now, on the `systemUptime` clock: the Mac's current event, `nil` elsewhere.
    @MainActor
    static func currentEvent() -> Event? {
        #if canImport(AppKit) && os(macOS)
            guard let event = NSApp?.currentEvent else {
                return nil
            }
            switch event.type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .otherMouseDown,
                .otherMouseUp:
                return Event(time: event.timestamp, isMouse: true)
            default:
                return Event(time: event.timestamp)
            }
        #else
            nil
        #endif
    }

    /// Seconds since the left mouse button last went down anywhere in the login session: the Mac's event source,
    /// `nil` elsewhere, where there's no mouse.
    ///
    /// Session-wide, so a press in another app counts too (condition 2). That's acceptable: a command is dropped for
    /// a press only when it comes with a fresh mouse event of ours, and then at most once per press. A press elsewhere
    /// inside the batch, followed by a click of ours on Undo after it, is a newer press, after the end, and goes
    /// through.
    @MainActor
    static func secondsSinceLeftMouseDown() -> Double? {
        #if canImport(AppKit) && os(macOS)
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        #else
            nil
        #endif
    }
}

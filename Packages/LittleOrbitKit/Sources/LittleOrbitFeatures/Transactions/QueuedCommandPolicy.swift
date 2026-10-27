import Foundation

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif

/// Whether an Undo or Redo was asked for while the last batch ran (#285, D398, D403, Tester2's N5 at c8c6594,
/// comment 6440723910; Tech Architect's review 5666694381).
///
/// While a batch saves, or the windows refresh after it, the main thread is blocked, so a click in an Edit menu left
/// open, or a ⌘Z, waits in the event queue. It's handled once the batch has ended and the busy flag is off, and would
/// undo one step more. The event still carries the time it happened, so a command whose event falls inside the last
/// batch, from its start to its end, is dropped. Event times and the batch's start and end are all seconds since the
/// system started: `NSEvent.timestamp` and `ProcessInfo.systemUptime` share that clock.
///
/// A menu item chosen with the mouse can be handled with the mouse-up as its event, later than the press that chose it
/// (Tester2 on 1f2eae8: a Redo pressed at +0.626 s, before the batch's end at +0.676 s, still ran). When a mouse button
/// was held as the batch ended, the press began inside it, so a mouse-up up to `pressAllowance` after the end is
/// dropped too. With no button held then, the press came after the end, and its click goes through (Tech Architect's
/// B3 on 0389f40).
///
/// AppKit never clears `NSApp.currentEvent`, so a command not driven by an event of its own (VoiceOver, Voice
/// Control or any other Accessibility press) sees whatever event came last. One from before the batch isn't
/// inside it, so the command goes through. One from inside the batch has already dropped its own command, so an
/// event drops at most one: the same timestamp again goes through.
enum QueuedCommandPolicy {
    /// The event a command is handled with: when it happened, and whether it's a mouse button going up.
    struct Event: Equatable, Sendable {
        var time: TimeInterval
        var isMouseUp = false
    }

    /// How long after a batch's end a mouse-up still counts as the end of a press that began inside it: a click
    /// held about as long as a deliberate one. A later click goes through.
    static let pressAllowance: TimeInterval = 0.3

    /// Whether to drop the command: its event happened while the last batch ran, `batch.start ≤ time ≤ batch.end`,
    /// or it's a mouse-up within `pressAllowance` after the end with a button held at the end (`heldAtEnd`), and it
    /// hasn't dropped a command already. With no current event, or no batch yet, it goes through.
    static func dropsCommand(
        event: Event?,
        lastBatch: ClosedRange<TimeInterval>?,
        heldAtEnd: Bool,
        lastDroppedEventTime: TimeInterval?,
    ) -> Bool {
        guard let event, let lastBatch, event.time != lastDroppedEventTime else {
            return false
        }
        if lastBatch.contains(event.time) {
            return true
        }
        return heldAtEnd && event.isMouseUp && event.time > lastBatch.upperBound
            && event.time - lastBatch.upperBound <= pressAllowance
    }

    /// `dropsCommand(event:lastBatch:heldAtEnd:lastDroppedEventTime:)` for an event that isn't a mouse-up.
    static func dropsCommand(
        eventTime: TimeInterval?,
        lastBatch: ClosedRange<TimeInterval>?,
        lastDroppedEventTime: TimeInterval?,
    ) -> Bool {
        dropsCommand(
            event: eventTime.map { Event(time: $0) },
            lastBatch: lastBatch,
            heldAtEnd: false,
            lastDroppedEventTime: lastDroppedEventTime,
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
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                return Event(time: event.timestamp, isMouseUp: true)
            default:
                return Event(time: event.timestamp)
            }
        #else
            nil
        #endif
    }

    /// Whether a mouse button is held down now, from the hardware's state rather than an event, since menu tracking
    /// may never pass its mouse-down to the app: the Mac's `NSEvent.pressedMouseButtons`, `false` elsewhere.
    @MainActor
    static func isMouseButtonHeld() -> Bool {
        #if canImport(AppKit) && os(macOS)
            NSEvent.pressedMouseButtons != 0
        #else
            false
        #endif
    }
}

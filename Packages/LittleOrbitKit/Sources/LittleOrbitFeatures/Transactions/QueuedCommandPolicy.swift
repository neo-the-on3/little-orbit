import Foundation

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif

/// Whether an Undo or Redo was asked for while the last batch ran (#285, D398, D403, Tester2's N5 at c8c6594,
/// comment 6440723910; Tech Architect's review 5666694381).
///
/// While a batch saves, the main thread is blocked, so a click in an Edit menu left open, or a ⌘Z, waits in the
/// event queue. It's handled once the batch has ended and the busy flag is off, and would undo one step more. The
/// event still carries the time it happened, so a command whose event falls inside the last batch, from its start
/// to its end, is dropped. Event times and the batch's start and end are all seconds since the system started:
/// `NSEvent.timestamp` and `ProcessInfo.systemUptime` share that clock.
///
/// AppKit never clears `NSApp.currentEvent`, so a command not driven by an event of its own (VoiceOver, Voice
/// Control or any other Accessibility press) sees whatever event came last. One from before the batch isn't
/// inside it, so the command goes through. One from inside the batch has already dropped its own command, so an
/// event drops at most one: the same timestamp again goes through.
enum QueuedCommandPolicy {
    /// Whether to drop the command: its event happened while the last batch ran, `batch.start ≤ eventTime ≤
    /// batch.end`, and hasn't dropped a command already. With no current event, or no batch yet, it goes through.
    static func dropsCommand(
        eventTime: TimeInterval?,
        lastBatch: ClosedRange<TimeInterval>?,
        lastDroppedEventTime: TimeInterval?,
    ) -> Bool {
        guard let eventTime, let lastBatch else {
            return false
        }
        return lastBatch.contains(eventTime) && eventTime != lastDroppedEventTime
    }

    /// The time of the event being handled now, on the `systemUptime` clock: the Mac's current event, `nil`
    /// elsewhere.
    @MainActor
    static func currentEventTime() -> TimeInterval? {
        #if canImport(AppKit) && os(macOS)
            NSApp?.currentEvent?.timestamp
        #else
            nil
        #endif
    }
}

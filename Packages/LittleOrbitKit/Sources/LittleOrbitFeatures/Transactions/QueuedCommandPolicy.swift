import Foundation

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif

/// Whether an Undo or Redo was asked for before the last batch ended (#285, D398, Tester2's N5 at c8c6594, comment
/// 6440723910).
///
/// While a batch saves, the main thread is blocked, so a click in an Edit menu left open, or a ⌘Z, waits in the
/// event queue. It's handled once the batch has ended and the busy flag is off, and would undo one step more. The
/// event still carries the time it happened, so a command whose event is no newer than the end of the last batch
/// is dropped (Tech Architect's ruling). Event times and the batch end are both seconds since the system started:
/// `NSEvent.timestamp` and `ProcessInfo.systemUptime` share that clock.
enum QueuedCommandPolicy {
    /// Whether to drop the command: its event happened at or before the end of the last batch. With no current
    /// event (a command not driven by one), or no batch yet, it goes through.
    static func dropsCommand(eventTime: TimeInterval?, lastBatchEnd: TimeInterval?) -> Bool {
        guard let eventTime, let lastBatchEnd else {
            return false
        }
        return eventTime <= lastBatchEnd
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

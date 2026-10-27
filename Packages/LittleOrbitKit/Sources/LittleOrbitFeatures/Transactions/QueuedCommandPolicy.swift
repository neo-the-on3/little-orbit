import Foundation

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif

/// Whether an Undo or Redo key equivalent typed while the last batch ran is one to drop (#285, D398, D403, D407;
/// Tester2's N5 at c8c6594, comment 6440723910; Tech Architect's reviews 5666694381 and 5670733886, and D407 on
/// 4839e5d).
///
/// While a batch runs, Edit › Undo and Redo are off (D407.1, `UndoCommandGate`): a click, Return in the menu,
/// VoiceOver or Voice Control finds them dimmed, and ⌘Z or ⇧⌘Z does nothing. That leaves one way in: while the save
/// or the windows' refresh block the main thread, a ⌘Z waits in the event queue, and AppKit dispatches it only once
/// the batch has ended and the items are on again. Its command would undo one step more (D407.2). So it's dropped.
/// What decides is the key-down being dispatched as the command runs (`EventDispatch`), never how old
/// `NSApp.currentEvent` is:
///
/// - A key-down: drops when its own time falls inside the last batch, `batch.start ≤ time ≤ batch.end`. A key-down
///   drops at most one command. A key equivalent is matched inside its key-down's dispatch,
///   `NSApplication.sendEvent(_:)` → the key window, then the main menu's `performKeyEquivalent(_:)`, so its
///   command sees it.
/// - Anything else, or nothing being dispatched: never drops. That covers a menu chosen with the mouse or keyboard,
///   whose tracking runs in a loop of its own, outside `sendEvent` (Tester2 on 4839e5d), Accessibility (VoiceOver,
///   Voice Control, an AXPress), and the toolbar. Those can't reach a command during the batch: the items are off
///   then, and the toolbar's buttons and `WindowUndoHistory.isBusy` too.
///
/// A key-down's time that can't be right, not a number, infinite, zero, negative or in the future, is never inside a
/// batch, so it fails open (m13 on 4839e5d).
///
/// Every time here is seconds since the system started, on one clock: `NSEvent.timestamp` and
/// `ProcessInfo.systemUptime`, which `LedgerUpdates` stamps the batch's start and end with.
enum QueuedCommandPolicy {
    /// The key-down a command is handled with, when it happened.
    struct Event: Equatable, Sendable {
        var time: TimeInterval
        /// The `NSEvent.EventType` raw value, for the signposts only; -1 when unknown.
        var type = -1
    }

    /// Whether to drop the command, for the key-down being dispatched as it runs: when its time fell inside the last
    /// batch and it hasn't dropped one already. With none being dispatched, or no batch yet, it goes through.
    static func dropsCommand(
        event: Event?,
        lastBatch: ClosedRange<TimeInterval>?,
        lastDroppedEventTime: TimeInterval?,
    ) -> Bool {
        guard let event, let lastBatch else {
            return false
        }
        return lastBatch.contains(event.time) && event.time != lastDroppedEventTime
    }

    /// `dropsCommand(event:lastBatch:lastDroppedEventTime:)` for a key-down at `eventTime`.
    static func dropsCommand(
        eventTime: TimeInterval?,
        lastBatch: ClosedRange<TimeInterval>?,
        lastDroppedEventTime: TimeInterval?,
    ) -> Bool {
        dropsCommand(
            event: eventTime.map { Event(time: $0) },
            lastBatch: lastBatch,
            lastDroppedEventTime: lastDroppedEventTime,
        )
    }

    #if canImport(AppKit) && os(macOS)
        /// The key-down an event AppKit dispatches is, on the `systemUptime` clock; `nil` for any other kind, which
        /// is never a command to drop.
        @MainActor
        static func event(for event: NSEvent) -> Event? {
            guard event.type == .keyDown else {
                return nil
            }
            return Event(time: event.timestamp, type: Int(event.type.rawValue))
        }
    #endif
}

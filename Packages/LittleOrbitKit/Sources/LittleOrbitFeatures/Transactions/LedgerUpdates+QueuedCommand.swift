import Foundation
import LittleOrbitCore

extension LedgerUpdates {
    /// Whether the command being handled is a key equivalent typed while the last batch ran, which waited in the
    /// event queue while the save blocked the main thread: an Undo or Redo then does nothing (`QueuedCommandPolicy`,
    /// D407.2). Decided by the key-down being dispatched as it runs (`dispatchingEvent`): with none, as for a menu,
    /// VoiceOver, Voice Control or an AXPress, it never drops. A `true` uses up the key-down, so the next command
    /// it's seen with goes through.
    ///
    /// Signposted on every check: `ledger.command.dispatch`, tagged `dropped`, `passed` or `noDispatch`, with, in
    /// order: the dispatched key-down's `NSEvent.EventType` raw value and time, the outermost event being
    /// dispatched's type (any kind), and the last batch's start and end; -1 for each one there's none of, and -2 as
    /// the outermost type when the app's `sendEvent` wrapper isn't in place; then `ledger.command.dropped` or
    /// `.passed` with the key-down's time (-1 for none).
    func dropsQueuedCommand() -> Bool {
        let event = dispatchingEvent()
        let drops = QueuedCommandPolicy.dropsCommand(
            event: event,
            lastBatch: lastBatch,
            lastDroppedEventTime: lastDroppedEventTime,
        )
        let tag: StaticString = drops ? "dropped" : event == nil ? "noDispatch" : "passed"
        BatchTrace.event(
            "ledger.command.dispatch",
            tag,
            values: [
                Double(event?.type ?? -1),
                event?.time ?? -1,
                Double(EventDispatch.shared.outermostType),
                lastBatch?.lowerBound ?? -1,
                lastBatch?.upperBound ?? -1,
            ],
        )
        // The key-down's time, to line up with `ledger.batch.start` and `.end`.
        BatchTrace.event(drops ? "ledger.command.dropped" : "ledger.command.passed", value: event?.time ?? -1)
        if drops, let event {
            lastDroppedEventTime = event.time
        }
        return drops
    }
}

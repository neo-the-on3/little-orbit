import Foundation
import LittleOrbitCore

extension LedgerUpdates {
    /// Whether the command being handled was asked for while the last batch ran, so it waited in the event queue
    /// while the save blocked the main thread: an Undo or Redo then does nothing (`QueuedCommandPolicy`). Decided by
    /// the input event being dispatched as it runs (`dispatchingEvent`, B5 on bab2ad8): with none, as for VoiceOver,
    /// Voice Control or an AXPress, it never drops. A `true` uses up the event, or for the left mouse the press, so
    /// the next command it's seen with goes through.
    ///
    /// Signposted on every check:
    /// - `ledger.command.press` with the press time (-1 for none, or one that can't be right), and
    ///   `ledger.command.pressAge` with the event source's raw seconds since it (-1 for no source);
    /// - `ledger.command.dispatch`, tagged `dropped`, `passed` or `noDispatch`, with, in order: the dispatched input
    ///   event's `NSEvent.EventType` raw value and time, the outermost event being dispatched's type (any kind), the
    ///   press time, the last batch's start and end, and the last key-down's time; -1 for each one there's none of,
    ///   and -2 as the outermost type when the app's `sendEvent` wrapper isn't in place;
    /// - then `ledger.command.dropped` or `.passed` with the dispatched event's time (-1 for none).
    func dropsQueuedCommand() -> Bool {
        let event = dispatchingEvent()
        let now = uptime()
        let age = secondsSincePress()
        let press = QueuedCommandPolicy.pressTime(now: now, secondsSince: age, launch: launchUptime)
        // The last key-down, through the same checks: for an item chosen with the keyboard in a menu opened with a
        // click (edge (b) on 4ea9bd6).
        let key = QueuedCommandPolicy.pressTime(now: now, secondsSince: secondsSinceKeyDown(), launch: launchUptime)
        BatchTrace.event("ledger.command.press", value: press ?? -1)
        BatchTrace.event("ledger.command.pressAge", value: age ?? -1)
        let drops = QueuedCommandPolicy.dropsCommand(
            event: event,
            pressTime: press,
            keyTime: key,
            lastBatch: lastBatch,
            lastDroppedEventTime: lastDroppedEventTime,
            lastDroppedPressTime: lastDroppedPressTime,
        )
        traceDispatch(event, press: press, key: key, drops: drops)
        // The event's time, to line up with `ledger.batch.start` and `.end`.
        BatchTrace.event(drops ? "ledger.command.dropped" : "ledger.command.passed", value: event?.time ?? -1)
        if drops, let event {
            if event.isMouse {
                lastDroppedPressTime = QueuedCommandPolicy.latestInput(pressTime: press, keyTime: key)
            } else {
                lastDroppedEventTime = event.time
            }
        }
        return drops
    }

    private func traceDispatch(
        _ event: QueuedCommandPolicy.Event?,
        press: TimeInterval?,
        key: TimeInterval?,
        drops: Bool,
    ) {
        let tag: StaticString = drops ? "dropped" : event == nil ? "noDispatch" : "passed"
        BatchTrace.event(
            "ledger.command.dispatch",
            tag,
            values: [
                Double(event?.type ?? -1),
                event?.time ?? -1,
                Double(EventDispatch.shared.outermostType),
                press ?? -1,
                lastBatch?.lowerBound ?? -1,
                lastBatch?.upperBound ?? -1,
                key ?? -1,
            ],
        )
    }
}

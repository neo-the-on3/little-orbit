#if DEBUG
    import Foundation
    import LittleOrbitCore

    #if canImport(AppKit) && os(macOS)
        import AppKit
    #endif

    /// Debug › Send Queued ⌘Z (n2 on #201): a ⌘Z typed during a batch, for Tester2 to send on demand, since a real
    /// one only queues while the save blocks the main thread. Chosen while a batch runs, it takes the press time
    /// then and waits for the batch to end; chosen outside one, it presses now. Either way it then posts a real ⌘Z
    /// key-down, stamped with the press time, for the key window to the event queue with
    /// `NSApp.postEvent(_:atStart:)`, so AppKit dequeues it as it does a queued key: the app's local key-down
    /// monitor (`UndoKeyMonitor`) sees it, then `LittleOrbitApplication.sendEvent`, the dispatch stack, the main
    /// menu's key equivalent and the SwiftUI Edit › Undo button (`QueuedCommandPolicy`, D407.2). Until 7c8a893 it
    /// was handed to `NSApp.sendEvent(_:)`, which skips local monitors: they run as an event is dequeued, so
    /// `ledger.keyMonitor.act` never fired for it (Tester2 at 7c8a893). In a batch
    /// that ⌘Z is dropped, `ledger.command.dispatch` tagged `dropped`, and nothing is undone; outside one, Undo runs
    /// once (`passed`). Debug › Send ⌘Z Right After Batch (`Stamp.atSend`), chosen during a batch, waits the same
    /// way but stamps the key-down when it sends it, just after the end: a ⌘Z typed as the batch ends, which no
    /// batch holds, so Undo must run once. Debug › Send ⇧⌘Z Right After Batch does the same with a ⇧⌘Z, for Redo.
    /// Each send is signposted as `debug.queuedUndo.send`, tagged `whenChosen`, `atSend` or `redoAtSend`, with the
    /// press time and the send's time, to line up with `ledger.batch.end`. Debug builds only: none of it is in a
    /// release build, which a test checks in the source.
    @MainActor
    public enum QueuedUndoKeyDebug {
        /// How often it checks whether the batch has ended; tests step their own.
        static let pollInterval = Duration.milliseconds(20)

        /// When the key-down is stamped: when the command was chosen (a ⌘Z queued during the batch), or as it's
        /// sent (a ⌘Z typed just after the batch's end).
        enum Stamp: Equatable, Sendable {
            case whenChosen
            case atSend
        }

        /// The key-down a command is: ⌘Z, "z" with ⌘, for Undo; ⇧⌘Z, "Z" with ⇧⌘, for Redo, as AppKit reports a
        /// typed one (Shift still applies to `charactersIgnoringModifiers`).
        struct Key: Equatable, Sendable {
            var characters: String
            var shift: Bool
        }

        static func key(for command: UndoCommandGate.Command) -> Key {
            command == .undo ? Key(characters: "z", shift: false) : Key(characters: "Z", shift: true)
        }

        /// The `debug.queuedUndo.send` tag.
        static func tag(_ stamp: Stamp, _ command: UndoCommandGate.Command) -> StaticString {
            switch (stamp, command) {
            case (.whenChosen, .undo): "whenChosen"
            case (.atSend, .undo): "atSend"
            case (.whenChosen, .redo): "redoWhenChosen"
            case (.atSend, .redo): "redoAtSend"
            }
        }

        /// Takes the press time now, or as it sends with `.atSend`, then runs `send` with it: once `updates` has no
        /// batch running, on a later turn than the batch's end, so the Edit menu is on again as it is for a queued
        /// key; or on the next turn when none was running. `uptime` is the `systemUptime` clock the batch is
        /// stamped with.
        @discardableResult
        static func press(
            updates: LedgerUpdates,
            stamp: Stamp = .whenChosen,
            command: UndoCommandGate.Command = .undo,
            uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
            sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
            send: @escaping @MainActor (_ pressTime: TimeInterval) -> Void,
        ) -> Task<Void, Never> {
            let chosen = uptime()
            return Task { @MainActor in
                repeat {
                    await sleep(pollInterval)
                } while updates.isBatchRunning
                let now = uptime()
                let pressTime = stamp == .atSend ? now : chosen
                BatchTrace.event("debug.queuedUndo.send", tag(stamp, command), values: [pressTime, now])
                send(pressTime)
            }
        }

        #if canImport(AppKit) && os(macOS)
            /// The menu command: a ⌘Z key-down (⇧⌘Z with `redo`) for the key window as it was when chosen, posted
            /// to the end of the event queue with `NSApp.postEvent(_:atStart:)` once any batch running then has
            /// ended, so it's dequeued, and seen by the local key-down monitor, like a typed key. Nothing when there
            /// was no key window. `rightAfterBatch` stamps it as it's sent (`Stamp.atSend`).
            public static func sendQueuedUndo(
                updates: LedgerUpdates,
                rightAfterBatch: Bool = false,
                redo: Bool = false,
            ) {
                guard let window = NSApp.keyWindow else {
                    return
                }
                let windowNumber = window.windowNumber
                let command: UndoCommandGate.Command = redo ? .redo : .undo
                let key = key(for: command)
                let stamp: Stamp = rightAfterBatch ? .atSend : .whenChosen
                press(updates: updates, stamp: stamp, command: command) { pressTime in
                    let event = NSEvent.keyEvent(
                        with: .keyDown,
                        location: .zero,
                        modifierFlags: key.shift ? [.command, .shift] : .command,
                        timestamp: pressTime,
                        windowNumber: windowNumber,
                        context: nil,
                        characters: key.characters,
                        charactersIgnoringModifiers: key.characters,
                        isARepeat: false,
                        keyCode: 6,
                    )
                    if let event {
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            }
        #endif
    }
#endif

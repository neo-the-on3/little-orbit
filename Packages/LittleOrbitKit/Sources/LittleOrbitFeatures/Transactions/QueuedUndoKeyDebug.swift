#if DEBUG
    import Foundation

    #if canImport(AppKit) && os(macOS)
        import AppKit
    #endif

    /// Debug › Send Queued ⌘Z (n2 on #201): a ⌘Z typed during a batch, for Tester2 to send on demand, since a real
    /// one only queues while the save blocks the main thread. Chosen while a batch runs, it takes the press time
    /// then and waits for the batch to end; chosen outside one, it presses now. Either way it then sends a real ⌘Z
    /// key-down, stamped with the press time, for the key window through `NSApp.sendEvent(_:)`, the way AppKit
    /// dispatches a queued key: so it goes through `LittleOrbitApplication.sendEvent`, the dispatch stack, the
    /// main menu's key equivalent and the SwiftUI Edit › Undo button (`QueuedCommandPolicy`, D407.2). In a batch
    /// that ⌘Z is dropped, `ledger.command.dispatch` tagged `dropped`, and nothing is undone; outside one, Undo runs
    /// once (`passed`). Debug builds only: none of it is in a release build, which a test checks in the source.
    @MainActor
    public enum QueuedUndoKeyDebug {
        /// How often it checks whether the batch has ended; tests step their own.
        static let pollInterval = Duration.milliseconds(20)

        /// Takes the press time now, then runs `send` with it: once `updates` has no batch running, on a later turn
        /// than the batch's end, so the Edit menu is on again as it is for a queued key; or on the next turn when
        /// none was running. `uptime` is the `systemUptime` clock the batch is stamped with.
        @discardableResult
        static func press(
            updates: LedgerUpdates,
            uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
            sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
            send: @escaping @MainActor (_ pressTime: TimeInterval) -> Void,
        ) -> Task<Void, Never> {
            let pressTime = uptime()
            return Task { @MainActor in
                repeat {
                    await sleep(pollInterval)
                } while updates.isBatchRunning
                send(pressTime)
            }
        }

        #if canImport(AppKit) && os(macOS)
            /// The menu command: a ⌘Z key-down for the key window as it was when chosen, sent through
            /// `NSApp.sendEvent(_:)` once any batch running then has ended. Nothing when there was no key window.
            public static func sendQueuedUndo(updates: LedgerUpdates) {
                guard let window = NSApp.keyWindow else {
                    return
                }
                let windowNumber = window.windowNumber
                press(updates: updates) { pressTime in
                    let event = NSEvent.keyEvent(
                        with: .keyDown,
                        location: .zero,
                        modifierFlags: .command,
                        timestamp: pressTime,
                        windowNumber: windowNumber,
                        context: nil,
                        characters: "z",
                        charactersIgnoringModifiers: "z",
                        isARepeat: false,
                        keyCode: 6,
                    )
                    if let event {
                        NSApp.sendEvent(event)
                    }
                }
            }
        #endif
    }
#endif

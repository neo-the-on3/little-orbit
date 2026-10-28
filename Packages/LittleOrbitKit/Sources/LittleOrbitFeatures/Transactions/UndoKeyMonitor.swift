#if canImport(AppKit) && os(macOS)
    import AppKit
    import LittleOrbitCore

    /// The app's local key-down monitor for ⌘Z and ⇧⌘Z (n2 on #201, Tech Architect's option (d)): when Edit › Undo
    /// or Redo is still disabled just after a batch's end although the gate is open, it runs the command as the item
    /// would, through the gate and `undo:` or `redo:` down the responder chain, and consumes the key-down. Every
    /// other key-down, and these in every other case, goes on to AppKit untouched (`UndoKeyPolicy`). Installed once,
    /// by `FocusedUndoMenu`, and removed when it goes; it runs in the key-down's turn, with no hop.
    @MainActor
    final class UndoKeyMonitor {
        private var token: Any?
        /// Reads the undo manager ⌘Z reaches, as the Edit menu does, for whether the gate is closed now.
        private let read: @MainActor (_ gateClosed: Bool) -> UndoMenuItems
        /// Sends the command's action down the responder chain, as Edit › Undo and Redo do.
        private let send: @MainActor (UndoCommandGate.Command) -> Bool

        init(
            read: @escaping @MainActor (_ gateClosed: Bool) -> UndoMenuItems,
            send: @escaping @MainActor (UndoCommandGate.Command) -> Bool,
        ) {
            self.read = read
            self.send = send
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return consumed ? nil : event
            }
        }

        isolated deinit {
            remove()
        }

        /// Stops monitoring.
        func remove() {
            if let token {
                NSEvent.removeMonitor(token)
            }
            token = nil
        }

        /// Whether it ran the key-down's command, and so consumes it.
        private func handle(_ event: NSEvent) -> Bool {
            let gate = UndoCommandGate.shared
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
            let characters = event.charactersIgnoringModifiers
            let keyModifiers = Self.policyModifiers(modifiers)
            // Cheap first: most key-downs aren't ⌘Z or ⇧⌘Z.
            if let reason = UndoKeyPolicy.keyReason(characters: characters, modifiers: keyModifiers) {
                #if DEBUG
                    Self.tracePass(reason, event)
                #endif
                return false
            }
            let window = event.window
            let items = read(gate.isClosed)
            let input = UndoKeyPolicy.Input(
                characters: characters,
                modifiers: keyModifiers,
                isAppKeyWindow: UndoKeyWindowPolicy.isAppKeyWindow(
                    eventWindow: window,
                    keyWindow: NSApp.keyWindow,
                    appWindows: NSApp.windows,
                    isKey: { $0.isKeyWindow },
                    parent: { $0.sheetParent ?? $0.parent },
                ),
                isMenuTracking: UndoCommandGate.mainIsTracking(),
                gateClosed: gate.isClosed,
                canUndo: items.canUndo,
                canRedo: items.canRedo,
                undoItemEnabled: Self.editItem(.undo)?.isEnabled,
                redoItemEnabled: Self.editItem(.redo)?.isEnabled,
            )
            #if DEBUG
                Self.tracePass(UndoKeyPolicy.reason(input), event)
            #endif
            guard case .act(let command) = UndoKeyPolicy.decide(input) else {
                return false
            }
            let key = QueuedCommandPolicy.event(for: event)
            let dispatching = EventDispatch.shared.current == key
            #if DEBUG
                BatchTrace.event(
                    "ledger.keyMonitor.act",
                    command == .undo ? "undoItemDisabledGateOpen" : "redoItemDisabledGateOpen",
                    values: [event.timestamp, dispatching ? 1 : 0],
                )
            #endif
            // The key-down must be the one being dispatched, so a ⌘Z queued during the batch is dropped by its
            // time (D403); a monitor that runs before `sendEvent` adds it, as `sendEvent` would.
            if dispatching {
                _ = gate.perform(command, send: send)
            } else {
                let entry = EventDispatch.Entry(type: Int(event.type.rawValue), input: key)
                _ = EventDispatch.shared.dispatching(entry) { gate.perform(command, send: send) }
            }
            return true
        }

        #if DEBUG
            /// `ledger.keyMonitor.pass` on every key-down the monitor sees, tagged with `UndoKeyPolicy.Reason`, with
            /// the event's time, its key code and its modifier flags: why ⌘Z or ⇧⌘Z did or didn't act (Tester2 at
            /// 7c8a893). Debug builds only; a release build has no call.
            private static func tracePass(_ reason: UndoKeyPolicy.Reason, _ event: NSEvent) {
                BatchTrace.event(
                    "ledger.keyMonitor.pass",
                    reason.tag,
                    values: [event.timestamp, Double(event.keyCode), Double(event.modifierFlags.rawValue)],
                )
            }
        #endif

        private static func policyModifiers(_ flags: NSEvent.ModifierFlags) -> UndoKeyPolicy.Modifiers {
            var modifiers: UndoKeyPolicy.Modifiers = []
            let named: [(NSEvent.ModifierFlags, UndoKeyPolicy.Modifiers)] = [
                (.command, .command), (.shift, .shift), (.option, .option), (.control, .control),
                (.function, .function),
            ]
            var rest = flags
            for (flag, modifier) in named where flags.contains(flag) {
                modifiers.insert(modifier)
                rest.remove(flag)
            }
            if !rest.isEmpty {
                modifiers.insert(.other)
            }
            return modifiers
        }

        /// Edit › Undo or Redo in the main menu, found by its key equivalent (⌘Z, or ⇧⌘Z written either way) or its
        /// action, never its localized title.
        static func editItem(_ command: UndoCommandGate.Command) -> NSMenuItem? {
            guard let mainMenu = NSApp?.mainMenu else {
                return nil
            }
            for menu in mainMenu.items.compactMap({ $0.submenu }) {
                if let item = menu.items.first(where: { matches($0, command) }) {
                    return item
                }
            }
            return nil
        }

        private static func matches(_ item: NSMenuItem, _ command: UndoCommandGate.Command) -> Bool {
            if item.action == command.action {
                return true
            }
            let flags = item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
            let key = item.keyEquivalent
            switch command {
            case .undo:
                return key == "z" && flags == .command
            case .redo:
                return (key == "z" && flags == [.command, .shift]) || (key == "Z" && flags == .command)
            }
        }
    }
#endif

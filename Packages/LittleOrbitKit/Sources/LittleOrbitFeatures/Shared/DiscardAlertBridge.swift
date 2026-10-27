#if canImport(SwiftUI) && canImport(AppKit) && os(macOS)
    import AppKit
    import SwiftUI

    // Why AppKit and not a SwiftUI alert (B3, D388.5): SwiftUI's .alert on the Mac moves the cancel-role button
    // last, and AppKit then gives Esc to a button by its title (Cancel or OK) or its order, not its role. Three
    // alert variants (0e7e63b, 82974ca and 96031b5) all read AXCancelButton = Discard Changes, so Esc would have
    // thrown the edits away. An NSAlert lets us set each button's key ourselves: Esc on Keep Editing, nothing on
    // Discard Changes, and no Return on either.

    extension View {
        /// The Mac's “Discard Changes?” (D300.1, D388.5): the alert from `makeDiscardAlert`, shown as a sheet on
        /// the edit sheet's window. Keep Editing, or the sheet ending any other way, leaves the
        /// edits as they are; only Discard Changes calls `onDiscard`. Either way `isPresented` goes back to false.
        func discardAlert(isPresented: Binding<Bool>, message: String?, onDiscard: @escaping () -> Void) -> some View {
            background {
                DiscardAlertPresenter(isPresented: isPresented, message: message, onDiscard: onDiscard)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }

    /// “Discard Changes?” as an NSAlert (D388.5). Keep Editing is added first and Discard Changes second, but
    /// AppKit draws Discard Changes on top and Keep Editing below. Keep Editing, the first button, has Esc as its
    /// key, which also takes away the Return NSAlert gives the first button, so no button has Return. Discard
    /// Changes has no key and no destructive styling, and the warning style draws no caution badge.
    @MainActor
    func makeDiscardAlert(title: String, message: String?, keepEditing: String, discard: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message ?? ""
        let keepButton = alert.addButton(withTitle: keepEditing)
        keepButton.keyEquivalent = "\u{1b}"
        let discardButton = alert.addButton(withTitle: discard)
        discardButton.keyEquivalent = ""
        discardButton.hasDestructiveAction = false
        return alert
    }

    /// Whether the discard alert's `response` was Discard Changes, its second button. Esc clicks Keep Editing, the
    /// first; any other ending, such as the sheet being closed under it, keeps the edits.
    func discardAlertDiscards(_ response: NSApplication.ModalResponse) -> Bool {
        response == .alertSecondButtonReturn
    }

    /// Shows the discard alert on its window while `isPresented` is true. With no window to show it on, it
    /// shows nothing and keeps the edits.
    private struct DiscardAlertPresenter: NSViewRepresentable {
        @Binding var isPresented: Bool
        let message: String?
        let onDiscard: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context _: Context) -> NSView {
            NSView()
        }

        func updateNSView(_ view: NSView, context: Context) {
            let coordinator = context.coordinator
            coordinator.isPresented = $isPresented
            coordinator.onDiscard = onDiscard
            if isPresented, coordinator.alert == nil {
                // On the next turn, after SwiftUI's update, so the binding isn't written during it.
                let message = message
                DispatchQueue.main.async { [weak view, weak coordinator] in
                    coordinator?.present(on: view?.window ?? NSApp.keyWindow, message: message)
                }
            } else if !isPresented, let alert = coordinator.alert {
                alert.window.sheetParent?.endSheet(alert.window, returnCode: .cancel)
            }
        }

        @MainActor
        final class Coordinator {
            var isPresented: Binding<Bool>?
            var onDiscard: (() -> Void)?
            private(set) var alert: NSAlert?

            func present(on window: NSWindow?, message: String?) {
                guard alert == nil, isPresented?.wrappedValue == true else {
                    return
                }
                guard let window else {
                    isPresented?.wrappedValue = false
                    return
                }
                let alert = makeDiscardAlert(
                    title: DiscardText.title,
                    message: message,
                    keepEditing: DiscardText.keepEditing,
                    discard: DiscardText.discard,
                )
                self.alert = alert
                alert.beginSheetModal(for: window) { [weak self] response in
                    MainActor.assumeIsolated {
                        self?.finish(response)
                    }
                }
            }

            private func finish(_ response: NSApplication.ModalResponse) {
                alert = nil
                isPresented?.wrappedValue = false
                if discardAlertDiscards(response) {
                    onDiscard?()
                }
            }
        }
    }
#endif

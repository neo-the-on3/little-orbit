#if canImport(SwiftUI) && canImport(UIKit) && os(iOS)
    import SwiftUI
    import UIKit

    extension View {
        /// The edit sheet's discard prompt for a swipe down (D300.1). While `isDirty`, a swipe down can't close
        /// the sheet and asks “Discard Changes?” at the top centre instead. Discard Changes calls `onDiscard`, which
        /// closes the sheet; Keep Editing leaves the edits as they are. SwiftUI has no hook for a swipe attempt, so
        /// a small UIKit bridge reports it. The Cancel button gets its own dialog with
        /// `discardsChangesFromCancel(confirmation:onDiscard:)`.
        func confirmsDiscardingChanges(
            isDirty: Bool,
            confirmation: Binding<DiscardConfirmation>,
            onDiscard: @escaping () -> Void,
        ) -> some View {
            interactiveDismissDisabled(isDirty)
                .background {
                    DismissAttemptObserver(isDirty: isDirty) { isDirty in
                        _ = confirmation.wrappedValue.requestDismiss(isDirty: isDirty, from: .swipe)
                    }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                }
                .discardDialog(isPresented: confirmation.isPresentedFromSwipe, onDiscard: onDiscard)
        }

        /// The Cancel button's “Discard Changes?” (D300.1), attached to the button so the iOS 26 popover
        /// points at it. The button asks with `requestDismiss(isDirty:from: .cancel)`.
        func discardsChangesFromCancel(
            confirmation: Binding<DiscardConfirmation>,
            onDiscard: @escaping () -> Void,
        ) -> some View {
            discardDialog(isPresented: confirmation.isPresentedFromCancel, onDiscard: onDiscard)
        }

        private func discardDialog(isPresented: Binding<Bool>, onDiscard: @escaping () -> Void) -> some View {
            confirmationDialog(DiscardText.title, isPresented: isPresented, titleVisibility: .visible) {
                Button(DiscardText.discard, role: .destructive, action: onDiscard)
                Button(DiscardText.keepEditing, role: .cancel) {}
            }
        }
    }

    /// Reports a swipe down that the sheet refused (UIAdaptivePresentationControllerDelegate's
    /// presentationControllerDidAttemptToDismiss). It wraps the sheet's existing delegate and passes everything
    /// else on to it, so SwiftUI's own handling is unchanged. SwiftUI can set its own delegate again after ours,
    /// for example when `interactiveDismissDisabled` changes, so the bridge installs again as the view appears and
    /// lays out, on every update, and once more on the next main-queue turn, after SwiftUI's own update.
    private struct DismissAttemptObserver: UIViewControllerRepresentable {
        let isDirty: Bool
        let onAttempt: (_ isDirty: Bool) -> Void

        func makeUIViewController(context _: Context) -> Controller {
            Controller()
        }

        func updateUIViewController(_ controller: Controller, context _: Context) {
            // The relay reads the state at the swipe, not a copy captured by an earlier update.
            controller.relay.isDirty = isDirty
            controller.relay.request = onAttempt
            controller.install()
            DispatchQueue.main.async { [weak controller] in
                controller?.install()
            }
        }

        final class Controller: UIViewController {
            let relay = DismissAttemptRelay()
            private var proxy: DismissAttemptProxy?

            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                install()
            }

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                install()
            }

            override func viewDidLayoutSubviews() {
                super.viewDidLayoutSubviews()
                install()
            }

            /// Makes our proxy the sheet's presentation delegate if it isn't already. It never wraps a proxy,
            /// ours or another bridge's, so the delegate chain can't grow or loop.
            func install() {
                guard let presentation = presentationController else {
                    return
                }
                let current = presentation.delegate
                let step = DismissAttemptInstall.step(
                    delegateIsOurProxy: proxy != nil && current === proxy,
                    delegateIsProxy: current is DismissAttemptProxy,
                )
                switch step {
                case .keep:
                    return
                case .adopt:
                    guard let other = current as? DismissAttemptProxy else {
                        return
                    }
                    other.relay = relay
                    proxy = other
                case .wrap:
                    let proxy = DismissAttemptProxy(original: current, relay: relay)
                    presentation.delegate = proxy
                    self.proxy = proxy
                }
            }
        }
    }

    private final class DismissAttemptProxy: NSObject, UIAdaptivePresentationControllerDelegate {
        private nonisolated(unsafe) weak var original: (any NSObjectProtocol)?
        var relay: DismissAttemptRelay

        init(original: (any UIAdaptivePresentationControllerDelegate)?, relay: DismissAttemptRelay) {
            self.original = original
            self.relay = relay
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            (original as? any UIAdaptivePresentationControllerDelegate)?
                .presentationControllerDidAttemptToDismiss?(presentationController)
            relay.attempt()
        }

        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }

        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }
#endif

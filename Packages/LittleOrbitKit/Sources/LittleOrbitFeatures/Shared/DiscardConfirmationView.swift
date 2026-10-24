#if canImport(SwiftUI) && canImport(UIKit) && os(iOS)
    import SwiftUI
    import UIKit

    extension View {
        /// The edit sheet's discard prompt (D300.1). While `isDirty`, a swipe down can't close the sheet and
        /// asks “Discard Changes?” instead, as Cancel does through `confirmation.requestDismiss(isDirty:)`.
        /// Discard Changes calls `onDiscard`, which closes the sheet; Keep Editing leaves the edits as they are.
        /// SwiftUI has no hook for a swipe attempt, so a small UIKit bridge reports it.
        func confirmsDiscardingChanges(
            isDirty: Bool,
            confirmation: Binding<DiscardConfirmation>,
            onDiscard: @escaping () -> Void,
        ) -> some View {
            interactiveDismissDisabled(isDirty)
                .background {
                    DismissAttemptObserver {
                        _ = confirmation.wrappedValue.requestDismiss(isDirty: isDirty)
                    }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                }
                .confirmationDialog(
                    DiscardText.title,
                    isPresented: confirmation.isPresented,
                    titleVisibility: .visible,
                ) {
                    Button(DiscardText.discard, role: .destructive, action: onDiscard)
                    Button(DiscardText.keepEditing, role: .cancel) {}
                }
        }
    }

    /// Reports a swipe down that the sheet refused (UIAdaptivePresentationControllerDelegate's
    /// presentationControllerDidAttemptToDismiss). It wraps the sheet's existing delegate and passes everything
    /// else on to it, so SwiftUI's own handling is unchanged.
    private struct DismissAttemptObserver: UIViewControllerRepresentable {
        let onAttempt: () -> Void

        func makeUIViewController(context _: Context) -> Controller {
            Controller()
        }

        func updateUIViewController(_ controller: Controller, context _: Context) {
            controller.onAttempt = onAttempt
            controller.install()
        }

        final class Controller: UIViewController {
            var onAttempt: () -> Void = {}
            private var proxy: DismissAttemptProxy?

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                install()
            }

            func install() {
                guard let presentation = presentationController else {
                    return
                }
                if let proxy, presentation.delegate === proxy {
                    proxy.onAttempt = onAttempt
                    return
                }
                let proxy = DismissAttemptProxy(original: presentation.delegate, onAttempt: onAttempt)
                presentation.delegate = proxy
                self.proxy = proxy
            }
        }
    }

    private final class DismissAttemptProxy: NSObject, UIAdaptivePresentationControllerDelegate {
        private nonisolated(unsafe) weak var original: (any NSObjectProtocol)?
        var onAttempt: () -> Void

        init(original: (any UIAdaptivePresentationControllerDelegate)?, onAttempt: @escaping () -> Void) {
            self.original = original
            self.onAttempt = onAttempt
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            (original as? any UIAdaptivePresentationControllerDelegate)?
                .presentationControllerDidAttemptToDismiss?(presentationController)
            onAttempt()
        }

        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }

        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }
#endif

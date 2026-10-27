#if canImport(SwiftUI) && canImport(UIKit) && os(iOS)
    import OSLog
    import SwiftUI
    import UIKit

    extension View {
        /// The edit sheet's discard prompt for a swipe down (D300.1). While `isDirty`, a swipe down can't close
        /// the sheet and asks “Discard Changes?” at the top centre instead, with `message` if the sheet has one
        /// (D388.1). Discard Changes calls `onDiscard`, which closes the sheet; Keep Editing leaves the edits as they
        /// are. SwiftUI has no hook for a swipe attempt, so a small UIKit bridge reports it. The Cancel button gets
        /// its own dialog with `discardsChangesFromCancel(confirmation:message:onDiscard:)`. Use it once per sheet,
        /// on the sheet's root view: one discard bridge per sheet.
        func confirmsDiscardingChanges(
            isDirty: Bool,
            confirmation: Binding<DiscardConfirmation>,
            message: String? = nil,
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
                .discardDialog(isPresented: confirmation.isPresentedFromSwipe, message: message, onDiscard: onDiscard)
        }

        /// The Cancel button's “Discard Changes?” (D300.1), attached to the button so the iOS 26 popover
        /// points at it. The button asks with `requestDismiss(isDirty:from: .cancel)`.
        func discardsChangesFromCancel(
            confirmation: Binding<DiscardConfirmation>,
            message: String? = nil,
            onDiscard: @escaping () -> Void,
        ) -> some View {
            discardDialog(isPresented: confirmation.isPresentedFromCancel, message: message, onDiscard: onDiscard)
        }
    }

    /// Reports a swipe down that the sheet refused (UIAdaptivePresentationControllerDelegate's
    /// presentationControllerDidAttemptToDismiss). It wraps the sheet's existing delegate and passes everything
    /// else on to it, so SwiftUI's own handling is unchanged.
    ///
    /// It installs on the presentation controller of the sheet's presented root controller, found through the
    /// bridge's parents or, if those don't lead to it, the view's responder chain. It never asks its own
    /// controller for a presentation controller: that controller isn't presented, so UIKit would make a new
    /// one for it that no swipe ever reaches. SwiftUI can set its own delegate again after ours, for example when
    /// `interactiveDismissDisabled` changes, so the bridge installs again as the view appears and lays out, on
    /// every update, and once more on the next main-queue turn, after SwiftUI's own update. It only sets the
    /// delegate: whether the sheet is modal is left to `interactiveDismissDisabled` (#167). Its proxy also
    /// refuses dismissal while there are unsaved edits, in case that flag lands late. One bridge per sheet.
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
            private lazy var installer = DismissAttemptInstaller<PresentedSheet>(relay: relay)

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

            /// Makes our proxy the sheet's presentation delegate if it isn't already. It never wraps a proxy, ours
            /// or another bridge's, so the delegate chain can't grow or loop. It leaves `isModalInPresentation`
            /// alone: `interactiveDismissDisabled(isDirty)` is its only writer, and a write here, including from
            /// the deferred re-install, could put back a stale `false` and let the first swipe close an edited
            /// sheet (#167).
            func install() {
                guard let root = sheetRoot(), let presentation = root.presentationController else {
                    return
                }
                let step = installer.install(on: PresentedSheet(presentation: presentation))
                if step != .keep {
                    DiscardBridgeLog.installed(on: root, adopted: step == .adopt)
                }
            }

            /// The sheet's presented root: up the parents first, then, if they don't reach it, from the first
            /// controller in the view's responder chain. Only a presented controller is asked for its
            /// presentation controller.
            private func sheetRoot() -> UIViewController? {
                let isPresented: (UIViewController) -> Bool = { controller in
                    controller.presentingViewController?.presentedViewController === controller
                }
                let parentOf: (UIViewController) -> UIViewController? = { $0.parent }
                let own: UIViewController = self
                if let root = DismissAttemptInstall.presentedRoot(
                    from: own,
                    parent: parentOf,
                    isPresented: isPresented,
                ) {
                    return root
                }
                guard isViewLoaded else {
                    return nil
                }
                var responder = view.next
                while let next = responder {
                    if let controller = next as? UIViewController, controller !== self {
                        return DismissAttemptInstall.presentedRoot(
                            from: controller,
                            parent: parentOf,
                            isPresented: isPresented,
                        )
                    }
                    responder = next.next
                }
                return nil
            }
        }
    }

    /// The sheet's presentation controller, as the installer sees it: only its delegate.
    private struct PresentedSheet: DismissAttemptSheet {
        let presentation: UIPresentationController

        var delegateProxy: DismissAttemptProxy? {
            presentation.delegate as? DismissAttemptProxy
        }

        func adopt(_ proxy: DismissAttemptProxy, relay: DismissAttemptRelay) {
            proxy.relay = relay
        }

        func wrapDelegate(relay: DismissAttemptRelay) -> DismissAttemptProxy {
            let proxy = DismissAttemptProxy(original: presentation.delegate, relay: relay)
            presentation.delegate = proxy
            return proxy
        }
    }

    /// The sheet's presentation delegate while the bridge is installed: it refuses dismissal while there are
    /// unsaved edits, reports refused swipes, and passes everything else on to the delegate it wraps.
    private final class DismissAttemptProxy: NSObject, UIAdaptivePresentationControllerDelegate {
        private nonisolated(unsafe) weak var original: (any NSObjectProtocol)?
        var relay: DismissAttemptRelay

        init(original: (any UIAdaptivePresentationControllerDelegate)?, relay: DismissAttemptRelay) {
            self.original = original
            self.relay = relay
        }

        /// Refuses a swipe down while there are unsaved edits (the relay's live state), so UIKit calls
        /// presentationControllerDidAttemptToDismiss and the prompt shows even when SwiftUI's
        /// `interactiveDismissDisabled` lands late (#167). With none, it's the original delegate's answer, or true.
        /// It doesn't write `isModalInPresentation`: `interactiveDismissDisabled` stays its only writer.
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            let delegate = original as? any UIAdaptivePresentationControllerDelegate
            let ask = delegate?.presentationControllerShouldDismiss
            return relay.shouldDismiss(original: ask.map { ask in { ask(presentationController) } })
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            (original as? any UIAdaptivePresentationControllerDelegate)?
                .presentationControllerDidAttemptToDismiss?(presentationController)
            DiscardBridgeLog.attempt(isDirty: relay.isDirty)
            relay.attempt()
        }

        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }

        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }

    /// Debug builds only: where the discard bridge installed and when a refused swipe reached it, to check D300.1
    /// in Console (subsystem LittleOrbit, category DiscardBridge). Only controller type names and a flag: never a
    /// path, a name or any other user data.
    @MainActor
    private enum DiscardBridgeLog {
        #if DEBUG
            private static let logger = Logger(subsystem: "LittleOrbit", category: "DiscardBridge")
        #endif

        static func installed(on controller: UIViewController, adopted: Bool) {
            #if DEBUG
                let kind = String(describing: type(of: controller))
                let how = adopted ? "adopted an existing proxy" : "installed"
                logger.debug("Discard bridge \(how, privacy: .public) on \(kind, privacy: .public)")
            #endif
        }

        static func attempt(isDirty: Bool) {
            #if DEBUG
                logger.debug("Discard bridge: refused swipe reported, unsaved edits: \(isDirty, privacy: .public)")
            #endif
        }
    }
#endif

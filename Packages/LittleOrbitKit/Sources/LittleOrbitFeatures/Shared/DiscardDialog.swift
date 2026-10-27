#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    extension View {
        /// “Discard Changes?” (D300.1), with `message` under the title when the sheet has one (D388.1) and none
        /// otherwise. On iPhone and iPad it is a confirmation dialog with Discard Changes (destructive) and Keep
        /// Editing (cancel role). On the Mac it is an AppKit alert shown as a sheet on the window, where Esc chooses
        /// Keep Editing and no key chooses Discard Changes (D388.5); Shared/DiscardAlertBridge.swift says why.
        @ViewBuilder
        func discardDialog(isPresented: Binding<Bool>, message: String?, onDiscard: @escaping () -> Void) -> some View {
            #if os(macOS)
                discardAlert(isPresented: isPresented, message: message, onDiscard: onDiscard)
            #else
                if let message {
                    confirmationDialog(DiscardText.title, isPresented: isPresented, titleVisibility: .visible) {
                        discardButtons(onDiscard: onDiscard)
                    } message: {
                        Text(message)
                    }
                } else {
                    confirmationDialog(DiscardText.title, isPresented: isPresented, titleVisibility: .visible) {
                        discardButtons(onDiscard: onDiscard)
                    }
                }
            #endif
        }

        #if !os(macOS)
            /// The prompt's two buttons (D300.1), straight in the dialog's actions.
            @ViewBuilder
            private func discardButtons(onDiscard: @escaping () -> Void) -> some View {
                Button(DiscardText.discard, role: .destructive, action: onDiscard)
                Button(DiscardText.keepEditing, role: .cancel) {}
            }
        #endif
    }

    #if os(macOS)
        extension View {
            /// The Cancel button's “Discard Changes?” on the Mac (D300.1), where Esc also chooses Cancel. The
            /// button asks with `requestDismiss(isDirty:from: .cancel)`. A Mac sheet has no swipe down.
            func discardsChangesFromCancel(
                confirmation: Binding<DiscardConfirmation>,
                message: String? = nil,
                onDiscard: @escaping () -> Void,
            ) -> some View {
                discardDialog(isPresented: confirmation.isPresentedFromCancel, message: message, onDiscard: onDiscard)
            }
        }
    #endif
#endif

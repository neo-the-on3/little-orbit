#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    extension View {
        /// Asks before deleting several transactions (D164.5): "Delete 5 Transactions" and Cancel, with the
        /// message "You can undo this." and no default button, so Return never deletes. A confirmation dialog on
        /// iOS and iPadOS (iOS 26 may hide its Cancel button; tapping outside cancels), an alert on macOS.
        func bulkDeleteConfirmation(
            _ prompt: BulkDeletePrompt?,
            onConfirm: @escaping (BulkDeletePrompt) -> Void,
            onCancel: @escaping () -> Void,
        ) -> some View {
            modifier(BulkDeleteConfirmation(prompt: prompt, onConfirm: onConfirm, onCancel: onCancel))
        }
    }

    private struct BulkDeleteConfirmation: ViewModifier {
        let prompt: BulkDeletePrompt?
        let onConfirm: (BulkDeletePrompt) -> Void
        let onCancel: () -> Void

        func body(content: Content) -> some View {
            #if os(iOS)
                content.confirmationDialog(
                    prompt?.title ?? "",
                    isPresented: isPresented,
                    titleVisibility: .visible,
                    presenting: prompt,
                    actions: actions,
                    message: message,
                )
            #else
                content.alert(
                    prompt?.title ?? "",
                    isPresented: isPresented,
                    presenting: prompt,
                    actions: actions,
                    message: message,
                )
            #endif
        }

        /// Shown while there's a prompt; every way out, including tapping outside, runs a button's action.
        private var isPresented: Binding<Bool> {
            Binding(get: { prompt != nil }, set: { _ in })
        }

        @ViewBuilder
        private func actions(_ prompt: BulkDeletePrompt) -> some View {
            Button(prompt.confirmTitle, role: .destructive) { onConfirm(prompt) }
            Button("Cancel", role: .cancel) { onCancel() }
        }

        private func message(_ prompt: BulkDeletePrompt) -> some View {
            Text(prompt.message)
        }
    }
#endif

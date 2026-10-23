#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// What Edit Expense's buttons do on the stored record (Figma 175:1994). Each runs once the sheet has
    /// closed. `nil` leaves a button out: Refund… only for an expense that can take one, Duplicate not on a
    /// refund (UI Designer, 23 Oct; D237.3).
    struct TransactionFormActions {
        var refund: (() -> Void)?
        var duplicate: (() -> Void)?
        var delete: () -> Void
    }

    /// Refund…, Duplicate, then Delete with its footnote, as the last sections of the edit sheet.
    struct TransactionFormActionSections: View {
        let actions: TransactionFormActions
        let deleteTitle: String
        let deleteFootnote: String?
        let hasUnsavedInput: Bool
        /// Closes the sheet, then runs the action.
        let close: (@escaping () -> Void) -> Void

        var body: some View {
            if actions.refund != nil || actions.duplicate != nil {
                Section {
                    if let refund = actions.refund {
                        ActionButton(title: "Refund…", kind: .refund, hasUnsavedInput: hasUnsavedInput) {
                            close(refund)
                        }
                    }
                    if let duplicate = actions.duplicate {
                        ActionButton(title: "Duplicate", kind: .duplicate, hasUnsavedInput: hasUnsavedInput) {
                            close(duplicate)
                        }
                    }
                }
            }
            Section {
                ActionButton(title: deleteTitle, kind: .delete, hasUnsavedInput: hasUnsavedInput, role: .destructive) {
                    close(actions.delete)
                }
            } footer: {
                if let deleteFootnote {
                    Text(deleteFootnote)
                }
            }
        }
    }

    /// One button. With unsaved edits, an action that asks first shows the sheet's Discard Changes
    /// confirmation anchored to this button, and runs only if it's confirmed.
    private struct ActionButton: View {
        let title: String
        let kind: TransactionFormAction
        let hasUnsavedInput: Bool
        var role: ButtonRole?
        let action: () -> Void
        @State private var confirmingDiscard = false

        var body: some View {
            Button(title, role: role) {
                if hasUnsavedInput && kind.asksToDiscardEdits {
                    confirmingDiscard = true
                } else {
                    action()
                }
            }
            .confirmationDialog(
                "Discard this transaction?",
                isPresented: $confirmingDiscard,
                titleVisibility: .visible,
            ) {
                Button("Discard Changes", role: .destructive, action: action)
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("The amount and details you entered will be lost.")
            }
        }
    }
#endif

#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// The account delete confirmation (D19, D165.2, D167): Hide Account is the default, Delete Account is
    /// destructive and never the default, and Cancel closes it. The words come from `AccountDeletePrompt`.
    ///
    /// It is shown by the view the user is on. From the Edit Account sheet, the sheet itself shows it, so it
    /// never waits for the sheet to close: an alert asked for while a sheet closed didn't show on iPad
    /// (Tester's #87 recheck, bug 3). Cancel keeps the sheet open.
    ///
    /// The prompt is this window's own (`AccountDeleteConfirmation`), so it never shows over another window
    /// (Tester's #87 B3).
    struct AccountDeleteAlert: ViewModifier {
        let confirmation: AccountDeleteConfirmation
        let model: AccountsViewModel
        /// Off while another view (the edit sheet) shows the prompt instead.
        let isActive: Bool
        let onHidden: () -> Void
        /// The account was deleted: record `change` and leave its screen.
        let onDeleted: (_ accountName: String, _ change: TransactionChange) -> Void

        func body(content: Content) -> some View {
            content.alert(
                confirmation.prompt?.title ?? "",
                isPresented: Binding(get: { isActive && confirmation.prompt != nil }, set: { _ in }),
                presenting: confirmation.prompt,
            ) { prompt in
                // Hide, the safe choice, is the default; Delete never is (D19, D165.2).
                Button(prompt.hideTitle) {
                    confirmation.hide()
                    onHidden()
                }
                .keyboardShortcut(.defaultAction)
                Button(prompt.deleteTitle, role: .destructive) {
                    let name = model.account(id: prompt.accountID)?.name ?? ""
                    // One step, "Undo Delete Account Household Card" (#93).
                    if let change = confirmation.confirm() {
                        onDeleted(name, change)
                    }
                }
                Button(prompt.cancelTitle, role: .cancel) { confirmation.cancel() }
            } message: { prompt in
                Text(prompt.message)
            }
        }
    }

    extension View {
        func accountDeleteAlert(
            _ confirmation: AccountDeleteConfirmation,
            model: AccountsViewModel,
            isActive: Bool = true,
            onHidden: @escaping () -> Void = {},
            onDeleted: @escaping (_ accountName: String, _ change: TransactionChange) -> Void,
        ) -> some View {
            modifier(
                AccountDeleteAlert(
                    confirmation: confirmation,
                    model: model,
                    isActive: isActive,
                    onHidden: onHidden,
                    onDeleted: onDeleted,
                )
            )
        }
    }
#endif

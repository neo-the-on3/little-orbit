#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// “Couldn’t Save Changes” on the transaction form, when its transaction was deleted elsewhere while the form was
    /// open. Dismissing it in any way, OK or Esc, closes the form (#264, D391.2): the binding tells the model, and
    /// the model's `closeRequested` closes the sheet.
    struct TransactionDeletedAlert: ViewModifier {
        @Bindable var model: TransactionFormViewModel
        let closeForm: () -> Void

        func body(content: Content) -> some View {
            content
                .alert(
                    model.alert?.title ?? "",
                    isPresented: $model.isAlertPresented,
                    presenting: model.alert,
                ) { _ in
                    Button("OK", role: .cancel) { model.acknowledgeAlert() }
                } message: { alert in
                    Text(alert.message)
                }
                .onChange(of: model.closeRequested) { _, close in
                    if close {
                        closeForm()
                    }
                }
        }
    }
#endif

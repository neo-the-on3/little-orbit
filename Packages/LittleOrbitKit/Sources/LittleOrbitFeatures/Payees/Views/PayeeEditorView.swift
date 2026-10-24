#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import SwiftUI

    /// Renaming a payee, in a sheet with Cancel and Save like the category editor. With unsaved edits, Cancel or
    /// a swipe down asks “Discard Changes?” first (D300.1). A name error shows under the name field (D295.4,
    /// D297.7).
    struct PayeeEditorView: View {
        @State private var model: PayeeEditorViewModel
        @State private var discard = DiscardConfirmation()
        @Environment(\.dismiss) private var dismiss

        init(model: PayeeEditorViewModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            Form {
                Section {
                    TextField(CategoryText.name, text: $model.name)
                        .accessibilityLabel(CategoryText.name)
                } footer: {
                    if let error = model.nameError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .confirmsDiscardingChanges(isDirty: model.hasUnsavedEdits, confirmation: $discard) { dismiss() }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CategoryText.cancel) {
                        if discard.requestDismiss(isDirty: model.hasUnsavedEdits) {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(CategoryText.save) {
                        if model.save() {
                            dismiss()
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
            .alert(
                model.alert?.title ?? "",
                isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
                presenting: model.alert,
            ) { _ in
                Button(CategoryText.okay) { model.alert = nil }
            } message: { alert in
                Text(alert.message)
            }
        }
    }

    extension PayeeEditorViewModel: Identifiable {
        public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
    }
#endif

#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import SwiftUI

    /// Merge Payees (#24 design, merge – choose name to keep): pick the payee whose name stays. Its footnote says
    /// what moves, which payees go, which last-used category stays (D291.5), and ends with “Merging can’t be
    /// undone.” (D287.3). The sheet with its Merge button is the confirmation.
    struct PayeeMergeSheet: View {
        @Bindable var model: PayeesViewModel
        /// The payees were merged.
        let onMerged: () -> Void
        /// This sheet's own alert, so the screen under it never shows the same one.
        @State private var alert: CategoryAlert?
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            List(selection: $model.survivorID) {
                Section {
                    ForEach(model.mergeRows) { row in
                        LabeledContent {
                            Text(row.transactions)
                        } label: {
                            Text(verbatim: row.name)
                        }
                        .tag(row.id)
                    }
                } header: {
                    Text(PayeeText.keepWhichName)
                } footer: {
                    Label(model.mergeFootnote, systemImage: "exclamationmark.circle")
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle(PayeeText.mergeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CategoryText.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Off without a payee to keep or with fewer than two selected, as after a failed merge's
                    // reload (Tech Architect NB2).
                    Button(CategoryText.merge) { confirm() }
                        .disabled(model.survivorID == nil || !model.canMerge)
                }
            }
            .alert(
                alert?.title ?? "",
                isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
                presenting: alert,
            ) { _ in
                Button(CategoryText.okay) { alert = nil }
            } message: { alert in
                Text(alert.message)
            }
        }

        private func confirm() {
            if model.merge() {
                onMerged()
                dismiss()
            } else {
                alert = model.alert
                model.alert = nil
            }
        }
    }
#endif

#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import SwiftUI

    /// Choosing a same-kind category: Merge “Groceries” into… (#24 design, merge) or the delete's Move To
    /// (#24 design, move target). Only the chosen kind's unarchived categories are listed (D291.4). The
    /// footnote ends with “Merging can’t be undone.” (D287.3). A refused merge shows D291.1's alert and the
    /// sheet stays open. Its rows were read once when it opened (`CategoryTargetChoice`), so the body reads
    /// nothing from the store.
    struct CategoryTargetSheet: View {
        let choice: CategoryTargetChoice
        /// The category was merged or deleted.
        let onRemoved: () -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            List {
                Section {
                    ForEach(choice.rows) { row in
                        Button {
                            choice.targetID = row.id
                        } label: {
                            HStack {
                                CategoryRowView(row: row)
                                Spacer()
                                if choice.targetID == row.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(.leading, row.isSubcategory ? 24 : 0)
                        }
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(choice.targetID == row.id ? .isSelected : [])
                    }
                } header: {
                    Text(choice.header)
                } footer: {
                    Text(choice.footer)
                }
            }
            .navigationTitle(choice.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CategoryText.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(choice.isMerge ? CategoryText.merge : CategoryText.move) {
                        if choice.confirm() {
                            onRemoved()
                            dismiss()
                        }
                    }
                    .disabled(choice.targetID == nil)
                }
            }
            .alert(
                choice.alert?.title ?? "",
                isPresented: Binding(get: { choice.alert != nil }, set: { if !$0 { choice.alert = nil } }),
                presenting: choice.alert,
            ) { _ in
                // OK only; the sheet stays open so another target can be chosen (D291.1).
                Button(CategoryText.okay) { choice.alert = nil }
            } message: { alert in
                Text(alert.message)
            }
        }
    }
#endif

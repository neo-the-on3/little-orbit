#if canImport(SwiftUI) && os(macOS)
    import SwiftUI

    /// The Mac Merge N Payees sheet (#24 design, Mac payees merge): the names, a Keep name: pop-up and the
    /// footnote. A failed merge shows “Couldn’t Save Changes” on this sheet, OK only, and the sheet stays open.
    /// Merging can’t be undone (D287.2).
    struct MetadataPayeeMergeSheet: View {
        @Bindable var merge: MetadataPayeeMerge
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text(merge.title)
                    .font(.headline)
                Text(merge.message)
                    .fixedSize(horizontal: false, vertical: true)
                Picker(MetadataText.keepName, selection: $merge.keptID) {
                    ForEach(merge.keepOptions) { row in
                        Text(verbatim: row.name).tag(Optional(row.id))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .frame(maxWidth: .infinity)
                Text(merge.footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(CategoryText.cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(CategoryText.merge) {
                        if merge.confirm() {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!merge.canMerge)
                }
            }
            .padding(20)
            .frame(width: 480)
            .alert(
                merge.alert?.title ?? "",
                isPresented: Binding(get: { merge.alert != nil }, set: { if !$0 { merge.alert = nil } }),
                presenting: merge.alert,
            ) { _ in
                Button(CategoryText.okay) { merge.alert = nil }
            } message: { alert in
                Text(alert.message)
            }
        }
    }
#endif

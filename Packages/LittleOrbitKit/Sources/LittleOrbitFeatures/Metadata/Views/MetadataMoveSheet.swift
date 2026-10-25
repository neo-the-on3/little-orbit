#if canImport(SwiftUI) && os(macOS)
    import SwiftUI

    /// The delete's Move To sheet on the Mac (#24 design, move target): only the category's own kind's
    /// unarchived categories (D291.4), the footnote, then Cancel and Move. Moving can’t be undone (D287.2).
    struct MetadataMoveSheet: View {
        let choice: CategoryTargetChoice
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(choice.title)
                    .font(.headline)
                Text(choice.header)
                    .foregroundStyle(.secondary)
                List(choice.rows, selection: Binding(get: { choice.targetID }, set: { choice.targetID = $0 })) { row in
                    CategoryRowView(row: row)
                        .padding(.leading, row.isSubcategory ? 24 : 0)
                }
                .frame(minHeight: 220)
                Text(choice.footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(CategoryText.cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(choice.isMerge ? CategoryText.merge : CategoryText.move) {
                        if choice.confirm() {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(choice.targetID == nil)
                }
            }
            .padding(20)
            .frame(width: 420)
            .alert(
                choice.alert?.title ?? "",
                isPresented: Binding(get: { choice.alert != nil }, set: { if !$0 { choice.alert = nil } }),
                presenting: choice.alert,
            ) { _ in
                Button(CategoryText.okay) { choice.alert = nil }
            } message: { alert in
                Text(alert.message)
            }
        }
    }
#endif

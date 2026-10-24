#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import SwiftUI

    /// iOS Settings › Payees (#24 design: list, select mode). Each payee shows its last-used category and how
    /// many transactions use it; tapping one opens its editor as a sheet. More › Select turns on select mode,
    /// where a tap selects the row and Merge… merges two or more payees.
    public struct PayeesView: View {
        @State private var model: PayeesViewModel
        @State private var editMode: EditMode = .inactive
        @State private var isMerging = false
        private let onRemoval: () -> Void

        /// `onRemoval` clears this window's Undo and Redo history after a merge (D287.4).
        public init(feature: PayeesFeature, onRemoval: @escaping () -> Void = {}) {
            _model = State(initialValue: feature.makeScreen())
            self.onRemoval = onRemoval
        }

        public var body: some View {
            List(selection: $model.selection) {
                Section {
                    ForEach(model.rows) { row in
                        if editMode.isEditing {
                            // The system selection handles the tap.
                            PayeeRowView(row: row)
                        } else {
                            rowButton(row)
                        }
                    }
                } footer: {
                    if !editMode.isEditing, model.hasPayees {
                        Text(PayeeText.listFooter)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay { emptyState }
            .searchable(
                text: $model.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: PayeeText.searchPrompt,
            )
            .environment(\.editMode, $editMode)
            .navigationTitle(PayeeText.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(item: $model.editor) { editor in
                NavigationStack {
                    PayeeEditorView(model: editor)
                }
            }
            .sheet(isPresented: $isMerging) {
                NavigationStack {
                    PayeeMergeSheet(model: model) {
                        withAnimation { editMode = .inactive }
                    }
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
            .onChange(of: editMode.isEditing) { _, isEditing in
                if !isEditing {
                    model.selection = []
                }
            }
            .onAppear {
                model.onRemoval = onRemoval
                model.load()
            }
        }

        /// A plain button that opens the row's editor sheet: no chevron, in the primary colour.
        private func rowButton(_ row: PayeeRow) -> some View {
            Button {
                model.openEditor(for: row.id)
            } label: {
                PayeeRowView(row: row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
        }

        @ViewBuilder private var emptyState: some View {
            if !model.hasPayees {
                ContentUnavailableView(
                    PayeeText.emptyTitle,
                    systemImage: "storefront",
                    description: Text(PayeeText.emptyMessage),
                )
                // The storefront is decorative. Hiding the icon inside the label didn't take effect in
                // ContentUnavailableView, so VoiceOver gets this instead: just the title and the message.
                .accessibilityRepresentation {
                    VStack {
                        Text(PayeeText.emptyTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text(PayeeText.emptyMessage)
                    }
                }
            } else if model.rows.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }

        @ToolbarContentBuilder private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .primaryAction) {
                if editMode.isEditing {
                    Button(CategoryText.done) {
                        withAnimation { editMode = .inactive }
                    }
                } else {
                    Menu {
                        Button(PayeeText.select, systemImage: "checkmark.circle") {
                            withAnimation { editMode = .active }
                        }
                        .disabled(!model.hasPayees)
                    } label: {
                        Label(CategoryText.more, systemImage: "ellipsis.circle")
                    }
                }
            }
            if editMode.isEditing {
                ToolbarItemGroup(placement: .bottomBar) {
                    Text(model.selectedText)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(PayeeText.mergeEllipsis) {
                        model.startMerge()
                        isMerging = true
                    }
                    .disabled(!model.canMerge)
                }
            }
        }
    }

    /// A payee: the storefront symbol, the name, and on the right its last-used category and count. VoiceOver
    /// reads only the name and "Shopping, 40 transactions", as one element; the decorative icon is hidden, as
    /// on the category rows.
    struct PayeeRowView: View {
        let row: PayeeRow

        var body: some View {
            LabeledContent {
                Text(row.detail)
            } label: {
                Label {
                    Text(verbatim: row.name)
                } icon: {
                    Image(systemName: "storefront")
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: row.name))
            .accessibilityValue(Text(verbatim: row.spokenDetail))
        }
    }
#endif

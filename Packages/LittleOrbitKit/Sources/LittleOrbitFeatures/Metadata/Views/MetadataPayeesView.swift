#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import SwiftUI

    /// The Metadata window's Payees table (#24 design, Mac payees): one multi-select table with Name, Last
    /// category and Used, the toolbar's Merge, and a status bar. Double-click renames a row in place; the
    /// context menu has Rename and Merge…. As on iOS, payees come from transactions, so there's no Add or Delete.
    struct MetadataPayeesView: View {
        @Bindable var model: MetadataPayeesViewModel
        @FocusState private var isRenameFocused: Bool

        var body: some View {
            VStack(spacing: 0) {
                table
                    .overlay {
                        if !model.hasPayees {
                            ContentUnavailableView(
                                PayeeText.emptyTitle,
                                systemImage: "storefront",
                                description: Text(PayeeText.emptyMessage),
                            )
                            // The storefront is decorative, so VoiceOver gets just the title, as a heading, and
                            // the message, as on iOS (#156).
                            .accessibilityRepresentation {
                                VStack {
                                    Text(PayeeText.emptyTitle)
                                        .accessibilityAddTraits(.isHeader)
                                    Text(PayeeText.emptyMessage)
                                }
                            }
                        }
                    }
                Divider()
                statusBar
            }
            .navigationTitle(MetadataText.windowTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.startMerge()
                    } label: {
                        Label(PayeeText.mergeEllipsis, systemImage: "arrow.triangle.merge")
                    }
                    .disabled(!model.canMerge)
                    .help(model.mergeHelp ?? PayeeText.mergeEllipsis)
                }
            }
            .sheet(item: $model.merge) { merge in
                MetadataPayeeMergeSheet(merge: merge)
            }
            .alert(
                model.screen.alert?.title ?? "",
                isPresented: Binding(
                    get: { model.screen.alert != nil },
                    set: { if !$0 { model.screen.alert = nil } },
                ),
                presenting: model.screen.alert,
            ) { _ in
                Button(CategoryText.okay) { model.screen.alert = nil }
            } message: { alert in
                Text(alert.message)
            }
        }

        // MARK: Table

        private var table: some View {
            Table(model.rows, selection: $model.selection) {
                TableColumn(CategoryText.name) { (row: MetadataPayeeRow) in
                    nameCell(row)
                }
                .width(min: 180, ideal: 360)
                TableColumn(MetadataText.lastCategoryColumn) { (row: MetadataPayeeRow) in
                    Text(verbatim: row.lastCategory)
                        .foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 140, max: 220)
                TableColumn(MetadataText.usedColumn) { (row: MetadataPayeeRow) in
                    Text(row.used, format: .number)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 50, ideal: 70, max: 120)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                contextMenu(ids)
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first {
                    model.beginRename(id)
                }
            }
            // Clicking away from the rename field saves it, as Return does; a name error keeps it open.
            .onChange(of: isRenameFocused) { _, isFocused in
                if !isFocused {
                    _ = model.commitRename()
                }
            }
        }

        @ViewBuilder
        private func nameCell(_ row: MetadataPayeeRow) -> some View {
            HStack(spacing: 8) {
                // The storefront chip is decorative, as on iOS.
                Image(systemName: "storefront")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.secondary, in: .circle)
                    .accessibilityHidden(true)
                if model.renaming?.payeeID == row.id {
                    TextField(CategoryText.name, text: $model.renameText)
                        .labelsHidden()
                        .focused($isRenameFocused)
                        .onSubmit { _ = model.commitRename() }
                        .onExitCommand { model.cancelRename() }
                        .onAppear { isRenameFocused = true }
                } else {
                    Text(verbatim: row.name)
                        .lineLimit(1)
                }
            }
        }

        @ViewBuilder
        private func contextMenu(_ ids: Set<UUID>) -> some View {
            if ids.count == 1, let id = ids.first {
                Button(MetadataText.rename) { model.beginRename(id) }
            } else if ids.count > 1 {
                Button(PayeeText.mergeEllipsis) {
                    if ids != model.selection {
                        model.selection = ids
                    }
                    model.startMerge()
                }
                .disabled(!model.canMerge(ids))
            }
        }

        // MARK: Status bar

        private var statusBar: some View {
            HStack {
                Text(model.statusText)
                    .font(.footnote)
                    .foregroundStyle(model.renaming?.nameError == nil ? Color.secondary : Color.red)
                Spacer()
            }
            .frame(minHeight: 16)
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
#endif

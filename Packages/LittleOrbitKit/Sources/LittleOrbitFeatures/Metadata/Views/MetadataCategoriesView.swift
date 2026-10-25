#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The Metadata window's Categories table (#24 design, Mac metadata manager): one flat, multi-select table
    /// of both kinds with Name, Kind and Used, the toolbar's Add, Merge and Delete, a status bar, and a
    /// collapsed Archived group with Unarchive under the table. Double-click renames a row in place; the
    /// context menu has Rename, Edit Category…, Merge… and Delete….
    struct MetadataCategoriesView: View {
        @Bindable var model: MetadataCategoriesViewModel
        @State private var isArchivedExpanded = false
        @FocusState private var isRenameFocused: Bool

        var body: some View {
            VStack(spacing: 0) {
                table
                archivedGroup
                Divider()
                statusBar
            }
            .navigationTitle(MetadataText.windowTitle)
            .toolbar { toolbar }
            .sheet(item: editorBinding) { editor in
                MetadataCategoryEditorSheet(model: editor, screen: model.screen)
            }
            .sheet(item: $model.merge) { merge in
                MetadataMergeSheet(merge: merge)
            }
            .sheet(item: $model.moveChoice) { choice in
                MetadataMoveSheet(choice: choice)
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
            .alert(
                model.screen.deletePrompt?.title ?? "",
                isPresented: Binding(
                    get: { model.screen.deletePrompt != nil },
                    set: { if !$0 { model.screen.deletePrompt = nil } },
                ),
                presenting: model.screen.deletePrompt,
            ) { prompt in
                deleteButtons(prompt)
            } message: { prompt in
                Text(prompt.message)
            }
            // Unarchiving a subcategory under an archived parent brings the parent back too, so it asks (D302).
            .alert(
                model.screen.unarchivePrompt?.title ?? "",
                isPresented: Binding(
                    get: { model.screen.unarchivePrompt != nil },
                    set: { if !$0 { model.screen.unarchivePrompt = nil } },
                ),
                presenting: model.screen.unarchivePrompt,
            ) { _ in
                Button(CategoryText.unarchive) { model.screen.confirmUnarchive() }
                    .keyboardShortcut(.defaultAction)
                Button(CategoryText.cancel, role: .cancel) { model.screen.unarchivePrompt = nil }
            } message: { prompt in
                Text(prompt.message)
            }
        }

        // MARK: Table

        private var table: some View {
            Table(model.rows, selection: $model.selection) {
                TableColumn(CategoryText.name) { (row: MetadataCategoryRow) in
                    nameCell(row)
                }
                .width(min: 180, ideal: 300)
                TableColumn(CategoryText.kindPicker) { (row: MetadataCategoryRow) in
                    Text(row.kindName)
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 100, max: 160)
                TableColumn(MetadataText.usedColumn) { (row: MetadataCategoryRow) in
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
            .onDeleteCommand { model.requestDelete() }
            // Clicking away from the rename field saves it, as Return does; a name error keeps it open.
            .onChange(of: isRenameFocused) { _, isFocused in
                if !isFocused {
                    _ = model.commitRename()
                }
            }
        }

        @ViewBuilder
        private func nameCell(_ row: MetadataCategoryRow) -> some View {
            HStack(spacing: 8) {
                MetadataChip(symbolName: row.symbolName, hue: row.hue, isSubcategory: row.isSubcategory)
                if model.renaming?.categoryID == row.id {
                    TextField(CategoryText.name, text: $model.renameText)
                        .labelsHidden()
                        .focused($isRenameFocused)
                        .onSubmit { _ = model.commitRename() }
                        .onExitCommand { model.cancelRename() }
                        .onAppear { isRenameFocused = true }
                } else {
                    // A subcategory reads with its parent, so it can be told apart in the flat table (UI Designer).
                    Text(row.name)
                        .lineLimit(1)
                        .accessibilityLabel(Text(verbatim: row.spokenName))
                }
            }
        }

        @ViewBuilder
        private func contextMenu(_ ids: Set<UUID>) -> some View {
            if ids.count == 1, let id = ids.first, let category = model.screen.category(id) {
                let isSubcategory = category.parentID != nil
                Button(MetadataText.rename) { model.beginRename(id) }
                Button(MetadataText.editCategory(isSubcategory: isSubcategory)) { model.openEditor(for: id) }
                Divider()
                Button(CategoryText.deleteRow(isSubcategory: isSubcategory), role: .destructive) {
                    model.selection = [id]
                    model.requestDelete()
                }
            } else if ids.count > 1 {
                Button(PayeeText.mergeEllipsis) {
                    model.selection = ids
                    model.startMerge()
                }
                .disabled(model.mergeAvailability(of: ids) != .available)
            }
        }

        // MARK: Archived

        @ViewBuilder private var archivedGroup: some View {
            let rows = model.archivedRows
            if !rows.isEmpty {
                Divider()
                DisclosureGroup(isExpanded: $isArchivedExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        List(rows) { row in
                            HStack {
                                // An archived subcategory under its archived parent is indented (UI Designer).
                                CategoryRowView(row: row)
                                    .padding(.leading, row.isIndented ? 24 : 0)
                                Spacer()
                                Button(CategoryText.unarchive) { model.screen.requestUnarchive(row.id) }
                            }
                        }
                        .frame(minHeight: 100, idealHeight: 160, maxHeight: 220)
                        Text(CategoryText.archivedFooter)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    LabeledContent {
                        Text(rows.count, format: .number)
                    } label: {
                        Label(CategoryText.archived, systemImage: "archivebox")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
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

        // MARK: Toolbar

        @ToolbarContentBuilder private var toolbar: some ToolbarContent {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(CategoryKind.allCases, id: \.self) { kind in
                        Button(MetadataText.addCategory(kind)) { model.openNewCategory(kind) }
                    }
                    Divider()
                    Button(CategoryText.addSubcategory) { model.openNewSubcategory() }
                        .disabled(model.subcategoryParent == nil)
                } label: {
                    Label(MetadataText.add, systemImage: "plus")
                }
                .help(MetadataText.add)
                Button {
                    model.startMerge()
                } label: {
                    Label(PayeeText.mergeEllipsis, systemImage: "arrow.triangle.merge")
                }
                .disabled(model.mergeAvailability != .available)
                .help(model.mergeHelp ?? PayeeText.mergeEllipsis)
                Button {
                    model.requestDelete()
                } label: {
                    Label(deleteTitle, systemImage: "trash")
                }
                .disabled(model.singleSelection == nil)
                .help(deleteTitle)
            }
        }

        private var deleteTitle: String {
            let isSubcategory = model.singleSelection.flatMap(model.screen.category)?.parentID != nil
            return CategoryText.deleteRow(isSubcategory: isSubcategory)
        }

        // MARK: Delete

        /// The same choices as iOS: Archive is the default (D19); the deleting choices can't be undone (D287.2).
        @ViewBuilder
        private func deleteButtons(_ prompt: CategoryDeletePrompt) -> some View {
            if prompt.isUnused {
                Button(CategoryText.delete, role: .destructive) {
                    _ = model.screen.deleteLeavingUncategorised(prompt.id)
                }
            } else {
                Button(CategoryText.archiveCategory) { _ = model.screen.archive(prompt.id) }
                    .keyboardShortcut(.defaultAction)
                Button(CategoryText.moveToAnother) { model.startMove(prompt.id) }
                Button(CategoryText.leaveUncategorised, role: .destructive) {
                    _ = model.screen.deleteLeavingUncategorised(prompt.id)
                }
            }
            Button(CategoryText.cancel, role: .cancel) { model.screen.deletePrompt = nil }
        }

        private var editorBinding: Binding<CategoryEditorViewModel?> {
            Binding(get: { model.screen.editor }, set: { model.screen.editor = $0 })
        }
    }

    /// A category's chip sized for a Mac table row: a top-level category's chip as drawn, and a smaller one for
    /// a subcategory, so it stands out in the flat table with no indent (D304.3, UI Designer). Both fit the
    /// row's height. VoiceOver skips it; the name says what it is.
    struct MetadataChip: View {
        let symbolName: String
        let hue: CategoryHue
        let isSubcategory: Bool
        @ScaledMetric private var size: CGFloat = 28
        @ScaledMetric private var subcategorySize: CGFloat = 20

        var body: some View {
            let side = isSubcategory ? subcategorySize : size
            Image(systemName: symbolName)
                .font(isSubcategory ? .caption : .body)
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(Color(hue.token), in: .circle)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
#endif

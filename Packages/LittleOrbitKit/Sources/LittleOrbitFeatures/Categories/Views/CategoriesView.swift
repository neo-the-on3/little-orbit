#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import SwiftUI

    /// iOS Settings › Categories (#24 design: tree, edit mode, Income with Archived). Expense and Income tabs,
    /// each top-level category with a disclosure arrow for its subcategories, Reorder in edit mode, and a
    /// collapsed Archived section with Unarchive at the bottom. Tapping a row opens its editor as a sheet, so the
    /// disclosure arrow is a row's only chevron (UI Designer's #155 review).
    public struct CategoriesView: View {
        @State private var model: CategoriesViewModel
        @State private var editMode: EditMode = .inactive
        @State private var expanded: Set<UUID> = []
        @State private var isArchivedExpanded = false
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric private var subcategoryIndent: CGFloat = 24
        private let onRemoval: () -> Void

        /// `onRemoval` clears this window's Undo and Redo history after a merge or delete (D287.4).
        public init(feature: CategoriesFeature, onRemoval: @escaping () -> Void = {}) {
            _model = State(initialValue: feature.makeScreen())
            self.onRemoval = onRemoval
        }

        public var body: some View {
            List {
                Section {
                    Picker(CategoryText.kindPicker, selection: $model.kind) {
                        ForEach(CategoryKind.allCases, id: \.self) { kind in
                            Text(CategoryText.kindName(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if editMode.isEditing {
                    reorderSections
                } else {
                    treeSection
                    archivedSection
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, $editMode)
            .navigationTitle(CategoryText.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(item: $model.editor) { editor in
                NavigationStack {
                    CategoryEditorView(model: editor, screen: model)
                }
                .openSheet(hasUnsavedEdits: { editor.hasUnsavedEdits }, close: { model.editor = nil })
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
            // Unarchiving a subcategory under an archived parent brings the parent back too, so it asks (D302).
            .alert(
                model.unarchivePrompt?.title ?? "",
                isPresented: Binding(
                    get: { model.unarchivePrompt != nil },
                    set: { if !$0 { model.unarchivePrompt = nil } },
                ),
                presenting: model.unarchivePrompt,
            ) { _ in
                Button(CategoryText.unarchive) { model.confirmUnarchive() }
                    .keyboardShortcut(.defaultAction)
                Button(CategoryText.cancel, role: .cancel) { model.unarchivePrompt = nil }
            } message: { prompt in
                Text(prompt.message)
            }
            .onAppear {
                model.onRemoval = onRemoval
                model.load()
            }
        }

        private var treeSection: some View {
            Section {
                ForEach(model.groups) { group in
                    if group.subcategories.isEmpty {
                        rowButton(group.parent)
                    } else {
                        // The label opens the editor and only the system chevron expands: a borderless
                        // button keeps the row's expand tap from swallowing the label's tap.
                        DisclosureGroup(isExpanded: expandedBinding(group.id)) {
                            ForEach(group.subcategories) { rowButton($0) }
                        } label: {
                            rowButton(group.parent)
                                .buttonStyle(.borderless)
                        }
                    }
                }
            } footer: {
                Text(CategoryText.listFooter)
            }
        }

        /// A plain button that opens the row's editor sheet: no chevron of its own.
        private func rowButton(_ row: CategoryRow) -> some View {
            Button {
                model.openEditor(for: row.id)
            } label: {
                CategoryRowView(row: row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
        }

        @ViewBuilder private var archivedSection: some View {
            let rows = model.archivedRows
            if !rows.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $isArchivedExpanded) {
                        ForEach(rows) { row in
                            // An archived subcategory under its archived parent is indented (UI Designer).
                            archivedRow(row)
                                .padding(.leading, row.isIndented ? subcategoryIndent : 0)
                        }
                    } label: {
                        LabeledContent {
                            Text(rows.count, format: .number)
                        } label: {
                            Label(CategoryText.archived, systemImage: "archivebox")
                        }
                    }
                } footer: {
                    Text(CategoryText.archivedFooter)
                }
            }
        }

        /// The row and its Unarchive button side by side, stacked at accessibility text sizes (NB7). The large
        /// bordered button keeps a 44 pt target.
        @ViewBuilder
        private func archivedRow(_ row: CategoryRow) -> some View {
            let unarchive = Button(CategoryText.unarchive) { model.requestUnarchive(row.id) }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: 44)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading) {
                    CategoryRowView(row: row)
                    unarchive
                }
            } else {
                HStack {
                    CategoryRowView(row: row)
                    Spacer()
                    unarchive
                }
            }
        }

        /// Edit mode: top-level categories reorder among themselves, and subcategories within their parent.
        @ViewBuilder private var reorderSections: some View {
            let groups = model.groups
            Section {
                ForEach(groups) { group in
                    CategoryRowView(row: group.parent)
                }
                .onMove { model.moveCategories(from: $0, to: $1) }
            } footer: {
                Text(CategoryText.reorderFooter)
            }
            ForEach(groups.filter { $0.subcategories.count > 1 }) { group in
                Section(group.parent.name) {
                    ForEach(group.subcategories) { CategoryRowView(row: $0) }
                        .onMove { model.moveSubcategories(of: group.id, from: $0, to: $1) }
                }
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
                        Button(CategoryText.addCategory, systemImage: "plus") {
                            model.openNewCategory()
                        }
                        Button(CategoryText.addSubcategory, systemImage: "plus.square.on.square") {
                            model.openNewSubcategory()
                        }
                        .disabled(!model.canAddSubcategory)
                        Button(CategoryText.reorder, systemImage: "arrow.up.arrow.down") {
                            withAnimation { editMode = .active }
                        }
                    } label: {
                        Label(CategoryText.more, systemImage: "ellipsis.circle")
                    }
                }
            }
        }

        private func expandedBinding(_ id: UUID) -> Binding<Bool> {
            Binding(
                get: { expanded.contains(id) },
                set: { isExpanded in
                    if isExpanded {
                        expanded.insert(id)
                    } else {
                        expanded.remove(id)
                    }
                },
            )
        }
    }

    extension CategoryEditorViewModel: Identifiable {
        public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
    }
#endif

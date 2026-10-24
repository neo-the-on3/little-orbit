#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The transaction form's category picker on iOS (#24 frames 16:7540 and 16:7702), in a sheet over the
    /// form with Cancel and Done. The search field is always visible; a typed name nothing matches offers
    /// Create. A tap checks a row; Done puts the checked category on the form, and Cancel leaves it as it was.
    /// Everything shown comes from the model's state, so drawing the sheet never reads the store.
    struct CategoryPickerView: View {
        @State private var model: CategoryPickerViewModel
        let onDone: (CategoryPickerViewModel) -> Void
        @Environment(\.dismiss) private var dismiss

        init(model: CategoryPickerViewModel, onDone: @escaping (CategoryPickerViewModel) -> Void) {
            _model = State(initialValue: model)
            self.onDone = onDone
        }

        var body: some View {
            NavigationStack {
                List {
                    if model.showsUncategorised {
                        Section {
                            choice(nil) {
                                HStack {
                                    CategoryChip(symbolName: "questionmark", hue: .gray)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading) {
                                        Text(model.uncategorisedTitle)
                                        Text(model.uncategorisedSubtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    if let title = model.createTitle {
                        let error = model.createError
                        Section {
                            Button {
                                model.create()
                            } label: {
                                LabeledContent {
                                    Text(model.createDetail)
                                } label: {
                                    Label(title, systemImage: "plus.circle")
                                }
                            }
                            .disabled(error != nil)
                        } footer: {
                            // An archived category has the name (D303): said inline, like the editor's errors.
                            if let error {
                                Text(error)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    let groups = model.groups
                    if !groups.isEmpty {
                        Section(model.sectionTitle) {
                            ForEach(groups) { group in
                                choice(group.parent.id) { CategoryRowView(row: group.parent) }
                                ForEach(group.subcategories) { row in
                                    choice(row.id) { CategoryRowView(row: row) }
                                }
                            }
                        }
                    }
                    if let row = model.archivedRow {
                        Section(model.archivedTitle) {
                            choice(row.id) { CategoryRowView(row: row) }
                        }
                    }
                }
                .searchable(
                    text: $model.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: model.searchPrompt,
                )
                .autocorrectionDisabled()
                .navigationTitle(model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(CategoryText.cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(CategoryText.done) {
                            onDone(model)
                            dismiss()
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
            }
        }

        /// A row that checks `id` when tapped, with the system checkmark and the selected trait when it's the
        /// checked one. It's a default-style button, so the List gives it the standard tap highlight and its
        /// 44 pt minimum height; the row's text is set to the primary label colour directly, so only the
        /// checkmark takes the accent tint (UI Designer's B1 on #159).
        private func choice<Content: View>(_ id: UUID?, @ViewBuilder label: () -> Content) -> some View {
            let isChecked = model.selection == id
            return Button {
                model.select(id)
            } label: {
                HStack {
                    label()
                        .foregroundStyle(Color(ThemeColor.labelPrimary))
                    Spacer()
                    if isChecked {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(isChecked ? .isSelected : [])
        }
    }

    extension CategoryPickerViewModel: Identifiable {
        public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
    }
#endif

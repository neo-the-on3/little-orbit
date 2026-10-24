#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The category and subcategory editor (#24 design, Edit Subcategory): the chip, the name, then Kind,
    /// Parent (a subcategory only, D287.1), Icon and Colour, and for an existing category Merge into… and
    /// Delete…. Adding and editing both show it in a sheet with Cancel and Save. With nothing entered or changed,
    /// Cancel closes it; otherwise Cancel, or a swipe down, asks “Discard Changes?” first (D300.1 and its
    /// amendment). A name error shows under the name field (D295.4).
    struct CategoryEditorView: View {
        @State private var model: CategoryEditorViewModel
        private let screen: CategoriesViewModel
        @State private var choice: CategoryTargetChoice?
        /// Set when the category was merged or deleted, so the editor closes once its sheet has.
        @State private var isRemoved = false
        @State private var discard = DiscardConfirmation()
        @Environment(\.dismiss) private var dismiss

        init(model: CategoryEditorViewModel, screen: CategoriesViewModel) {
            _model = State(initialValue: model)
            self.screen = screen
        }

        var body: some View {
            Form {
                // The chip has its own section, so no separator sits right above Name (UI Designer).
                Section {
                    CategoryChip(symbolName: model.symbolName, hue: model.hue)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section {
                    TextField(CategoryText.name, text: $model.name)
                        .accessibilityLabel(CategoryText.name)
                } footer: {
                    if let error = model.nameError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    LabeledContent(CategoryText.kindPicker, value: model.kindValue)
                    if model.isSubcategory {
                        Picker(CategoryText.parent, selection: $model.parentID) {
                            ForEach(model.parentOptions) { row in
                                Text(row.name).tag(Optional(row.id))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                    Picker(CategoryText.icon, selection: $model.symbolName) {
                        ForEach(model.symbolOptions) { option in
                            Label {
                                Text(option.name)
                            } icon: {
                                Image(systemName: option.symbol)
                                    .accessibilityHidden(true)
                            }
                            .accessibilityLabel(option.name)
                            .tag(option.symbol)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    if !model.isSubcategory {
                        colourPicker
                    }
                } header: {
                    Text(CategoryText.details)
                } footer: {
                    Text(model.footnote)
                }
                if let id = model.categoryID {
                    Section {
                        Button(CategoryText.mergeInto) { choice = screen.makeTargetChoice(.merge(id)) }
                        Button(CategoryText.deleteRow(isSubcategory: model.isSubcategory), role: .destructive) {
                            screen.requestDelete(id)
                        }
                    }
                }
            }
            .confirmsDiscardingChanges(isDirty: model.hasUnsavedEdits, confirmation: $discard) { dismiss() }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CategoryText.cancel) {
                        if discard.requestDismiss(isDirty: model.hasUnsavedEdits, from: .cancel) {
                            dismiss()
                        }
                    }
                    .discardsChangesFromCancel(confirmation: $discard) { dismiss() }
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
            .alert(
                screen.deletePrompt?.title ?? "",
                isPresented: Binding(
                    get: { screen.deletePrompt != nil },
                    set: { if !$0 { screen.deletePrompt = nil } },
                ),
                presenting: screen.deletePrompt,
            ) { prompt in
                deleteButtons(prompt)
            } message: { prompt in
                Text(prompt.message)
            }
            .sheet(item: $choice, onDismiss: closeIfRemoved) { choice in
                NavigationStack {
                    CategoryTargetSheet(choice: choice) { isRemoved = true }
                }
            }
        }

        private var colourPicker: some View {
            Picker(CategoryText.colour, selection: $model.hue) {
                ForEach(CategoryHue.allCases, id: \.self) { hue in
                    Label {
                        Text(model.colourName(hue))
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(Color(hue.token))
                            .accessibilityHidden(true)
                    }
                    .tag(hue)
                }
            }
            .pickerStyle(.navigationLink)
        }

        /// Archive is the default (D19); the two deleting choices can't be undone (D287.2).
        @ViewBuilder
        private func deleteButtons(_ prompt: CategoryDeletePrompt) -> some View {
            if prompt.isUnused {
                Button(CategoryText.delete, role: .destructive) {
                    if screen.deleteLeavingUncategorised(prompt.id) {
                        dismiss()
                    }
                }
            } else {
                Button(CategoryText.archiveCategory) {
                    if screen.archive(prompt.id) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button(CategoryText.moveToAnother) { choice = screen.makeTargetChoice(.move(prompt.id)) }
                Button(CategoryText.leaveUncategorised, role: .destructive) {
                    if screen.deleteLeavingUncategorised(prompt.id) {
                        dismiss()
                    }
                }
            }
            Button(CategoryText.cancel, role: .cancel) { screen.deletePrompt = nil }
        }

        private func closeIfRemoved() {
            if isRemoved {
                dismiss()
            }
        }
    }
#endif

#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// "Edit N Transactions" (Figma 29:2012): tick a field to change it for every selected row. Category is
    /// off for mixed kinds ("Mixed types"), and Payee skips transfers (D114). Return saves, Esc cancels.
    struct BulkEditView: View {
        @State private var model: BulkEditViewModel
        let onApplied: (TransactionChange) -> Void

        init(model: BulkEditViewModel, onApplied: @escaping (TransactionChange) -> Void) {
            _model = State(initialValue: model)
            self.onApplied = onApplied
        }
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                Text(model.title)
                    .font(.theme(Typography.MacOS.headline))
                Text("Ticked fields change on all selected transactions. Amounts and types stay as they are.")
                    .font(.theme(Typography.MacOS.footnote))
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                Form {
                    categoryRow
                    HStack {
                        Toggle("Payee", isOn: $model.editsPayee)
                        TextField("Payee", text: $model.payeeText, prompt: Text("None"))
                            .labelsHidden()
                            .accessibilityLabel("Payee")
                            .disabled(!model.editsPayee)
                    }
                    if let payeeNote = model.payeeNote {
                        note(payeeNote)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Toggle("Description", isOn: $model.editsDetails)
                        VStack(alignment: .leading) {
                            LimitedDescriptionField(text: model.details) { model.updateDetails($0) }
                                .labelsHidden()
                                .disabled(!model.editsDetails)
                            if let footnote = model.detailsFootnote {
                                note(footnote)
                            }
                        }
                    }
                    HStack {
                        Toggle("Date", isOn: $model.editsDate)
                        DatePicker("Date", selection: $model.date, displayedComponents: .date)
                            .labelsHidden()
                            .accessibilityLabel("Date")
                            .disabled(!model.editsDate)
                    }
                    HStack {
                        Toggle("Account", isOn: $model.editsAccount)
                        Picker("Account", selection: $model.accountID) {
                            ForEach(model.accountOptions) { option in
                                Text(option.name).tag(Optional(option.id))
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Account")
                        .disabled(!model.editsAccount)
                    }
                }
                HStack {
                    Text("Return saves · Esc cancels")
                        .font(.theme(Typography.MacOS.footnote))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(model.applyTitle) {
                        if let change = model.apply() {
                            onApplied(change)
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canApply)
                }
            }
            .padding(Layout.marginMacOS)
            .frame(minWidth: 460)
        }

        @ViewBuilder private var categoryRow: some View {
            HStack {
                Toggle("Category", isOn: $model.editsCategory)
                    .disabled(!model.isCategoryEnabled)
                // As in the entry sheet: Labels with icons in a section per parent, the chosen value as text,
                // and VoiceOver reads "Category, Groceries" (Tester's #87 blocker).
                Picker(selection: $model.categoryID) {
                    Label("Uncategorised", systemImage: "questionmark").tag(UUID?.none)
                    CategoryPickerSections(groups: model.categoryGroups)
                } label: {
                    Text("Category")
                } currentValueLabel: {
                    Text(model.categoryName)
                }
                .labelsHidden()
                .accessibilityLabel("Category")
                .accessibilityValue(model.categorySpokenValue)
                .disabled(!model.isCategoryEnabled || !model.editsCategory)
            }
            if let categoryNote = model.categoryNote {
                note(categoryNote)
            }
        }

        private func note(_ text: String) -> some View {
            Text(text)
                .font(.theme(Typography.MacOS.footnote))
                .foregroundStyle(Color(ThemeColor.labelSecondary))
        }
    }
#endif

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
                // Each toggle has its own VoiceOver name, "Change Payee", so it reads apart from its field. The
                // fields keep their hidden labels, which VoiceOver still reads: "Payee", "Category, Groceries".
                // With an accessibilityLabel on top of the hidden label, the tree showed "Payee, Payee" (#110).
                Form {
                    categoryRow
                    HStack {
                        Toggle("Payee", isOn: $model.editsPayee)
                            .accessibilityLabel(BulkEditText.changePayee)
                        TextField("Payee", text: $model.payeeText, prompt: Text("None"))
                            .labelsHidden()
                            .disabled(!model.editsPayee)
                    }
                    if let payeeNote = model.payeeNote {
                        note(payeeNote)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Toggle("Description", isOn: $model.editsDetails)
                            .accessibilityLabel(BulkEditText.changeDescription)
                        VStack(alignment: .leading) {
                            LimitedDescriptionField(text: model.details, hidesLabel: true) { model.updateDetails($0) }
                                .disabled(!model.editsDetails)
                            if let footnote = model.detailsFootnote {
                                note(footnote)
                            }
                        }
                    }
                    HStack {
                        Toggle("Date", isOn: $model.editsDate)
                            .accessibilityLabel(BulkEditText.changeDate)
                        DatePicker("Date", selection: $model.date, displayedComponents: .date)
                            .labelsHidden()
                            .disabled(!model.editsDate)
                    }
                    HStack {
                        Toggle("Account", isOn: $model.editsAccount)
                            .accessibilityLabel(BulkEditText.changeAccount)
                        Picker("Account", selection: $model.accountID) {
                            ForEach(model.accountOptions) { option in
                                Text(option.name).tag(Optional(option.id))
                            }
                        }
                        .labelsHidden()
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
                    .accessibilityLabel(BulkEditText.changeCategory)
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

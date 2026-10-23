#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// "Edit N Transactions" (Figma 29:2012, #34 frames for D222, D223 and D226): tick a field to change it for
    /// every selected row. Category is off for mixed kinds ("Mixed types") or a refund ("Includes refunds"),
    /// Payee skips transfers (D114), and the Account popup disables accounts no row can move to. Return saves,
    /// Esc cancels. It follows changes from other windows while open (D227.3).
    struct BulkEditView: View {
        @State private var model: BulkEditViewModel
        let updates: LedgerUpdates
        let onApplied: (TransactionChange) -> Void

        init(model: BulkEditViewModel, updates: LedgerUpdates, onApplied: @escaping (TransactionChange) -> Void) {
            _model = State(initialValue: model)
            self.updates = updates
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
                        // The picker shows the first row's own day in its stored zone; each row then moves to the
                        // picked day in its own zone, keeping its time (D229.4, D230.2).
                        DatePicker("Date", selection: $model.pickerDate, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.timeZone, model.pickerTimeZone)
                            .disabled(!model.editsDate)
                    }
                    accountRow
                }
                HStack {
                    Text("Return saves · Esc cancels")
                        .font(.theme(Typography.MacOS.footnote))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(model.applyTitle) {
                        let change = model.apply()
                        if let change {
                            onApplied(change)
                        }
                        // No message means it saved, or nothing changed and there's no step (D231.4).
                        if model.errorMessage == nil {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canApply)
                }
            }
            .padding(Layout.marginMacOS)
            .frame(minWidth: 460)
            .onChange(of: updates.revision) { model.reload() }
            // Nothing was saved and the sheet stays open with the first rule broken (D225.5), as the entry sheet.
            .alert(
                "Couldn’t save",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { _ in }),
            ) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }

        @ViewBuilder private var categoryRow: some View {
            HStack {
                Toggle("Category", isOn: $model.editsCategory)
                    .accessibilityLabel(BulkEditText.changeCategory)
                    .disabled(!model.isCategoryEnabled)
                // As in the entry sheet: Labels with icons in a section per parent, the chosen value as text,
                // and VoiceOver reads "Category, Groceries" (Tester's #87 blocker). When Category is off, the
                // popup says why: "Includes refunds" or "Mixed types".
                Picker(selection: $model.categoryID) {
                    Label("Uncategorised", systemImage: "questionmark").tag(UUID?.none)
                    CategoryPickerSections(groups: model.categoryGroups)
                } label: {
                    Text("Category")
                } currentValueLabel: {
                    Text(model.categoryPopupText)
                }
                .labelsHidden()
                .accessibilityValue(model.isCategoryEnabled ? model.categorySpokenValue : model.categoryPopupText)
                .disabled(!model.isCategoryEnabled || !model.editsCategory)
            }
            if let footnote = model.categoryFootnote {
                note(footnote)
            }
        }

        /// Accounts no row can move to are shown but disabled, with why as a subtitle; a mixed-currency selection
        /// turns Account off with "Mixed currencies" (D223.2, D226.3).
        @ViewBuilder private var accountRow: some View {
            HStack {
                Toggle("Account", isOn: $model.editsAccount)
                    .accessibilityLabel(BulkEditText.changeAccount)
                    .disabled(!model.isAccountEnabled)
                Picker(selection: $model.accountID) {
                    ForEach(model.accountOptions) { option in
                        accountItem(option)
                            .tag(Optional(option.id))
                            .selectionDisabled(!option.isEnabled)
                    }
                } label: {
                    Text("Account")
                } currentValueLabel: {
                    Text(model.accountPopupText)
                }
                .labelsHidden()
                .disabled(!model.isAccountEnabled || !model.editsAccount)
            }
            if let footnote = model.accountFootnote {
                note(footnote)
            }
        }

        @ViewBuilder private func accountItem(_ option: BulkAccountOption) -> some View {
            if let reason = option.disabledReason {
                Text(option.name) + Text(verbatim: "\n") + Text(reason)
            } else {
                Text(option.name)
            }
        }

        private func note(_ text: String) -> some View {
            Text(text)
                .font(.theme(Typography.MacOS.footnote))
                .foregroundStyle(Color(ThemeColor.labelSecondary))
        }
    }
#endif

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
        @Environment(WindowUndoHistory.self) private var undoHistory: WindowUndoHistory?
        /// Apply, while it runs (#285).
        @State private var applying: Task<Void, Never>?

        var body: some View {
            Group {
                // After half a second, the progress takes the fields' place in the same sheet (D398.3).
                if let progress = model.progress, progress.isShown {
                    BatchProgressView(progress: progress)
                } else {
                    fields
                }
            }
            // Apply can't be stopped once it starts: no Cancel, Esc or close (D398.3). If the window closes all the
            // same, nothing is written.
            .interactiveDismissDisabled(model.isApplying)
            .onDisappear { applying?.cancel() }
            // Apply found selected transactions deleted elsewhere (D393). OK, Esc or any dismissal sets the binding to
            // false, which drops them from the selection and keeps the sheet open with the ticked fields. When every
            // selected transaction was deleted, the model's `closeRequested` closes the sheet instead.
            .alert(
                model.alert?.title ?? "",
                isPresented: $model.isAlertPresented,
                presenting: model.alert,
            ) { _ in
                Button("OK", role: .cancel) { model.acknowledgeAlert() }
            } message: { alert in
                Text(alert.message)
            }
            .onChange(of: model.closeRequested) { _, close in
                if close {
                    dismiss()
                }
            }
        }

        private var fields: some View {
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
                        .disabled(model.isApplying)
                    Button(model.applyTitle) {
                        applying = Task { await apply() }
                    }
                    .keyboardShortcut(.defaultAction)
                    // Off while another window's Bulk Edit, or its Undo or Redo, runs (D398).
                    .disabled(!model.canApply || model.isApplying || undoHistory?.isBatchRunning == true)
                }
            }
            .padding(Layout.marginMacOS)
            .frame(minWidth: 460)
        }

        /// One Undo step for the whole edit, whose Undo and Redo run as a batch too (#285).
        private func apply() async {
            guard let change = await model.applyInBackground() else {
                return
            }
            onApplied(change)
            undoHistory?.markBulkEdit(change)
            dismiss()
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

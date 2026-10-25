#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The Mac New Budget and Edit Budget sheet (#25 part 5, Mac Budgets edit sheet frame), on part 3's form
    /// model: Name, Limit and Currency, the expense categories as checkboxes, Starts and Repeat, and the two
    /// carry-over checkboxes. Errors show in red under their own fields and Save stays off (D151). With edits,
    /// Cancel or Esc asks “Discard Changes?” first (D300.1); a new start or repeat for a budget with past periods
    /// asks “Recalculate Past Periods?” on Save (D307.7). Editing, Delete Budget… asks over the sheet, as Delete
    /// Account… does.
    struct MacBudgetFormSheet: View {
        /// The form, and the budget's detail model for Delete Budget… when editing.
        struct Item: Identifiable {
            let form: BudgetFormViewModel
            let detail: BudgetDetailViewModel?

            var id: ObjectIdentifier { form.id }
        }

        @Bindable private var model: BudgetFormViewModel
        private let detail: BudgetDetailViewModel?
        private let onDeleted: () -> Void
        @State private var confirmsDiscard = false
        @State private var asksToRecalculate = false
        @State private var confirmsDelete = false
        @State private var deleteAlert: CategoryAlert?
        @Environment(\.dismiss) private var dismiss

        init(item: Item, onDeleted: @escaping () -> Void) {
            self.model = item.form
            detail = item.form.isNew ? nil : item.detail
            self.onDeleted = onDeleted
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.space4) {
                Text(model.title)
                    .font(.theme(Typography.MacOS.headline))
                ScrollView {
                    form
                }
                buttons
            }
            .padding(Layout.marginMacOS)
            .frame(minWidth: 460, idealWidth: 500, minHeight: 480, idealHeight: 620)
            .confirmationDialog(DiscardText.title, isPresented: $confirmsDiscard) {
                Button(DiscardText.discard, role: .destructive) { dismiss() }
                Button(DiscardText.keepEditing, role: .cancel) {}
            }
            .alert(model.recalculationTitle, isPresented: $asksToRecalculate) {
                Button(CategoryText.save) { finish(model.save(confirmed: true)) }
                Button(CategoryText.cancel, role: .cancel) {}
            } message: {
                Text(model.recalculationMessage)
            }
            .alert(detail?.deleteTitle ?? "", isPresented: $confirmsDelete) {
                Button(CategoryText.delete, role: .destructive, action: delete)
                Button(CategoryText.cancel, role: .cancel) {}
            } message: {
                Text(detail?.deleteMessage ?? "")
            }
            .alert(
                shownAlert?.title ?? "",
                isPresented: Binding(get: { shownAlert != nil }, set: { if !$0 { clearAlerts() } }),
                presenting: shownAlert,
            ) { _ in
                Button(CategoryText.okay) { clearAlerts() }
            } message: { alert in
                Text(alert.message)
            }
        }

        private var form: some View {
            Form {
                Section {
                    TextField(BudgetText.nameHeader, text: $model.name, prompt: Text(BudgetText.namePrompt))
                    error(model.nameError)
                }
                Section {
                    TextField(BudgetText.limitHeader, text: $model.limitText, prompt: Text(model.limitPrompt))
                        .monospacedDigit()
                    error(model.limitError)
                    Picker(BudgetText.currency, selection: $model.currencyCode) {
                        ForEach(model.currencyOptions, id: \.self) { code in
                            Text(model.currencyTitle(for: code)).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    note(BudgetText.currencyFootnote)
                }
                Section {
                    LabeledContent(BudgetText.categoriesHeader) {
                        VStack(alignment: .leading, spacing: Spacing.space1) {
                            ForEach(model.categoryOptions) { option in
                                Toggle(option.name, isOn: categoryBinding(option.id))
                                    .toggleStyle(.checkbox)
                                    .disabled(model.isIncludedByParent(option.id))
                                    .padding(.leading, option.isSubcategory ? Spacing.space5 : 0)
                            }
                            error(model.categoriesError)
                            note(BudgetText.categoriesFootnote)
                        }
                    }
                }
                Section {
                    DatePicker(BudgetText.starts, selection: $model.startDate, displayedComponents: .date)
                        // Days are kept as calendar days; the picker shows them in UTC so none shifts.
                        .environment(\.timeZone, BudgetDays.calendar.timeZone)
                    Picker(BudgetText.repeatTitle, selection: $model.repeatChoice) {
                        ForEach(BudgetFormViewModel.RepeatChoice.allCases, id: \.self) { choice in
                            Text(model.repeatTitle(choice)).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    if model.repeatChoice == .custom {
                        Stepper(
                            BudgetText.every(model.customCount),
                            value: $model.customCount,
                            in: BudgetRecurrence.customRange,
                        )
                        .monospacedDigit()
                        Picker(BudgetText.unitLabel, selection: $model.customUnit) {
                            ForEach(BudgetRecurrenceUnit.allCases, id: \.self) { unit in
                                Text(model.unitTitle(unit)).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        note(BudgetText.customFootnote)
                    }
                    note(model.periodFootnote)
                }
                Section {
                    LabeledContent(BudgetText.carryOverHeader) {
                        VStack(alignment: .leading, spacing: Spacing.space1) {
                            Toggle(BudgetText.carryOverUnspent, isOn: $model.carriesOverUnspent)
                            Toggle(BudgetText.carryOverOverspending, isOn: $model.carriesOverOverspending)
                            note(BudgetText.carryOverFootnote)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .formStyle(.columns)
        }

        private var buttons: some View {
            HStack {
                if detail != nil {
                    Button(BudgetText.deleteBudgetEllipsis, role: .destructive) { confirmsDelete = true }
                }
                Spacer()
                Button(CategoryText.cancel) {
                    if model.hasUnsavedEdits {
                        confirmsDiscard = true
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)
                Button(CategoryText.save) { finish(model.save()) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
        }

        @ViewBuilder
        private func error(_ text: String?) -> some View {
            if let text {
                Text(text)
                    .font(.theme(Typography.MacOS.footnote))
                    .foregroundStyle(Color(ThemeColor.destructiveDefault))
            }
        }

        private func note(_ text: String) -> some View {
            Text(text)
                .font(.theme(Typography.MacOS.footnote))
                .foregroundStyle(Color(ThemeColor.labelSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }

        /// Ticked for a picked category or one its parent includes; a change toggles the one clicked.
        private func categoryBinding(_ id: UUID) -> Binding<Bool> {
            Binding(get: { model.isSelected(id) }, set: { _ in model.toggleCategory(id) })
        }

        private var shownAlert: CategoryAlert? {
            model.alert ?? deleteAlert
        }

        private func clearAlerts() {
            model.alert = nil
            deleteAlert = nil
        }

        private func finish(_ result: BudgetFormViewModel.SaveResult) {
            switch result {
            case .saved: dismiss()
            case .confirmRecalculation: asksToRecalculate = true
            case .notSaved: break
            }
        }

        private func delete() {
            guard let detail else {
                return
            }
            if detail.delete() {
                dismiss()
                onDeleted()
            } else {
                deleteAlert = detail.alert
                detail.alert = nil
            }
        }
    }

    /// The Mac Change Budget Limit sheet (#25 part 5), on part 4's detail model: the new limit, its error in red,
    /// and “Was ₹7,000.00.” With past periods, Save asks “Change limit to …?” first, with Apply from This Period
    /// (#25 AC 4, Mac Budgets change limit frame). With an edit, Cancel or Esc asks “Discard Changes?” (D300.1).
    struct MacBudgetLimitSheet: View {
        @Bindable var model: BudgetDetailViewModel
        /// Takes an alert to show once the sheet has closed, such as “This budget no longer exists.” (D309).
        let onAlert: (CategoryAlert) -> Void
        @State private var confirmsDiscard = false
        @State private var confirms = false
        @Environment(\.dismiss) private var dismiss

        init(model: BudgetDetailViewModel, onAlert: @escaping (CategoryAlert) -> Void) {
            self.model = model
            self.onAlert = onAlert
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.space4) {
                Text(BudgetText.changeBudgetLimit)
                    .font(.theme(Typography.MacOS.headline))
                Form {
                    TextField(BudgetText.limitHeader, text: $model.limitText)
                        .monospacedDigit()
                    if let error = model.limitError {
                        Text(error)
                            .font(.theme(Typography.MacOS.footnote))
                            .foregroundStyle(Color(ThemeColor.destructiveDefault))
                    }
                    Text(model.limitFootnote)
                        .font(.theme(Typography.MacOS.footnote))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .formStyle(.columns)
                HStack {
                    Spacer()
                    Button(CategoryText.cancel) {
                        if model.limitEdited {
                            confirmsDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(CategoryText.save) { finish(model.changeLimit()) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canChangeLimit)
                }
            }
            .padding(Layout.marginMacOS)
            .frame(minWidth: 380, idealWidth: 420)
            .confirmationDialog(DiscardText.title, isPresented: $confirmsDiscard) {
                Button(DiscardText.discard, role: .destructive) { dismiss() }
                Button(DiscardText.keepEditing, role: .cancel) {}
            }
            .alert(model.limitConfirmationTitle, isPresented: $confirms) {
                Button(BudgetText.applyFromThisPeriod) { finish(model.changeLimit(confirmed: true)) }
                    .keyboardShortcut(.defaultAction)
                Button(CategoryText.cancel, role: .cancel) {}
            } message: {
                Text(model.limitConfirmationMessage)
            }
        }

        private func finish(_ result: BudgetDetailViewModel.LimitChangeResult) {
            switch result {
            case .saved:
                dismiss()
            case .confirm:
                confirms = true
            case .notSaved:
                // A budget deleted meanwhile (D309): the screen says so once the sheet closes.
                if let alert = model.alert {
                    model.alert = nil
                    onAlert(alert)
                    dismiss()
                }
            }
        }
    }
#endif

#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The New Budget and Edit Budget sheet (#25 design: New budget – form, validation errors and Recalculate
    /// past periods frames): name, limit and currency, expense categories, start and repeat, and carry-over.
    /// Errors show in red under their own sections only, and Save stays off (D151, UI Designer's ruling 6). With
    /// edits, Cancel or a swipe down asks “Discard Changes?” first (D300.1). A new start or repeat for a budget
    /// with past periods asks “Recalculate Past Periods?” on Save (D307.7).
    struct BudgetFormView: View {
        @State private var model: BudgetFormViewModel
        @State private var discard = DiscardConfirmation()
        @State private var asksToRecalculate = false
        @Environment(\.dismiss) private var dismiss

        init(model: BudgetFormViewModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            Form {
                Section {
                    TextField(BudgetText.nameHeader, text: $model.name, prompt: Text(BudgetText.namePrompt))
                        .accessibilityLabel(BudgetText.nameHeader)
                } header: {
                    Text(BudgetText.nameHeader)
                } footer: {
                    errorText(model.nameError)
                }
                limitSection
                Section {
                    NavigationLink {
                        BudgetCategoriesView(model: model)
                    } label: {
                        LabeledContent(BudgetText.expenseCategories, value: model.categoriesSummary)
                    }
                } header: {
                    Text(BudgetText.categoriesHeader)
                } footer: {
                    footnote(BudgetText.categoriesFootnote, error: model.categoriesError)
                }
                Section {
                    DatePicker(BudgetText.starts, selection: $model.startDate, displayedComponents: .date)
                        // Days are kept as calendar days; the picker shows them in UTC so none shifts.
                        .environment(\.timeZone, BudgetDays.calendar.timeZone)
                    NavigationLink {
                        BudgetRepeatView(model: model)
                    } label: {
                        LabeledContent(BudgetText.repeatTitle, value: model.repeatSummary)
                    }
                } header: {
                    Text(BudgetText.periodHeader)
                } footer: {
                    Text(model.periodFootnote)
                }
                Section {
                    Toggle(BudgetText.carryOverUnspent, isOn: $model.carriesOverUnspent)
                    Toggle(BudgetText.carryOverOverspending, isOn: $model.carriesOverOverspending)
                } header: {
                    Text(BudgetText.carryOverHeader)
                } footer: {
                    Text(BudgetText.carryOverFootnote)
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
                    Button(CategoryText.save) { finish(model.save()) }
                        .disabled(!model.canSave)
                }
            }
            .confirmationDialog(model.recalculationTitle, isPresented: $asksToRecalculate, titleVisibility: .visible) {
                Button(CategoryText.save) { finish(model.save(confirmed: true)) }
                Button(CategoryText.cancel, role: .cancel) {}
            } message: {
                Text(model.recalculationMessage)
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

        private var limitSection: some View {
            Section {
                TextField(BudgetText.limitHeader, text: $model.limitText, prompt: Text(model.limitPrompt))
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                    .accessibilityLabel(BudgetText.limitHeader)
                Picker(BudgetText.currency, selection: $model.currencyCode) {
                    ForEach(model.currencyOptions, id: \.self) { code in
                        Text(model.currencyTitle(for: code)).tag(code)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text(BudgetText.limitHeader)
            } footer: {
                footnote(BudgetText.currencyFootnote, error: model.limitError)
            }
        }

        @ViewBuilder
        private func errorText(_ error: String?) -> some View {
            if let error {
                Text(error)
                    .foregroundStyle(Color(ThemeColor.destructiveDefault))
            }
        }

        /// A section's error, if any, above its footnote.
        private func footnote(_ text: String, error: String?) -> some View {
            VStack(alignment: .leading, spacing: Spacing.space1) {
                errorText(error)
                Text(text)
            }
        }

        private func finish(_ result: BudgetFormViewModel.SaveResult) {
            switch result {
            case .saved: dismiss()
            case .confirmRecalculation: asksToRecalculate = true
            case .notSaved: break
            }
        }
    }

    /// The form's Categories screen (#25 design: Categories – multi-select): unarchived expense categories, each
    /// parent followed by its indented subcategories. A picked parent includes its subcategories, which show
    /// picked and can't be picked on their own.
    struct BudgetCategoriesView: View {
        let model: BudgetFormViewModel

        var body: some View {
            List(selection: selection) {
                Section {
                    ForEach(model.categoryOptions) { option in
                        BudgetCategoryOptionRow(option: option)
                            .selectionDisabled(model.isIncludedByParent(option.id))
                            .tag(option.id)
                    }
                } header: {
                    Text(model.categoriesHeader)
                } footer: {
                    Text(BudgetText.categoriesScreenFootnote)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle(BudgetText.categoriesHeader)
            .navigationBarTitleDisplayMode(.inline)
        }

        /// What shows ticked, included subcategories too. A change toggles what was tapped.
        private var selection: Binding<Set<UUID>> {
            Binding(
                get: { Set(model.categoryOptions.map(\.id).filter { model.isSelected($0) }) },
                set: { newValue in
                    let current = Set(model.categoryOptions.map(\.id).filter { model.isSelected($0) })
                    for id in current.symmetricDifference(newValue) {
                        model.toggleCategory(id)
                    }
                },
            )
        }
    }

    /// A Categories row: the chip, the name and, under a parent, “3 subcategories”. VoiceOver reads the name and
    /// the count as one element; the icon is decorative.
    struct BudgetCategoryOptionRow: View {
        let option: BudgetCategoryOption

        var body: some View {
            HStack {
                CategoryChip(symbolName: option.symbolName, hue: option.hue, isSubcategory: option.isSubcategory)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(option.name)
                        .lineLimit(2)
                    if let subtitle = option.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, option.isSubcategory ? Spacing.space6 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(option.name)
            .accessibilityValue(option.subtitle ?? "")
        }
    }

    /// The form's Repeat screen (#25 design: Repeat – custom): weekly, fortnightly, monthly, yearly or every 1–99
    /// days, weeks, months or years, with the current period and the two after it.
    struct BudgetRepeatView: View {
        @Bindable var model: BudgetFormViewModel

        var body: some View {
            Form {
                Section {
                    Picker(BudgetText.repeatTitle, selection: $model.repeatChoice) {
                        ForEach(BudgetFormViewModel.RepeatChoice.allCases, id: \.self) { choice in
                            Text(model.repeatTitle(choice)).tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if model.repeatChoice == .custom {
                    Section {
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
                    } header: {
                        Text(BudgetText.custom)
                    } footer: {
                        Text(BudgetText.customFootnote)
                    }
                }
                Section {
                    ForEach(model.nextPeriods) { period in
                        LabeledContent {
                            if period.isCurrent {
                                Text(BudgetText.thisPeriod)
                            }
                        } label: {
                            Text(period.dates)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text(BudgetText.nextPeriods)
                }
            }
            .navigationTitle(BudgetText.repeatTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    extension BudgetFormViewModel: Identifiable {
        public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
    }
#endif

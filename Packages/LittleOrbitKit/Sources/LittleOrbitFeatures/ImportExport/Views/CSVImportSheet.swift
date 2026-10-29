#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// The import sheet: Columns, the target account when the file names none, Match, Review and the summary.
    /// Standard grouped forms, lists and controls; all logic is in `CSVImportViewModel`.
    struct CSVImportSheet: View {
        @Bindable var model: CSVImportViewModel
        /// For the shared store-change signal (D327.1).
        let feature: ImportExportFeature
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                stepContainer
                    .navigationTitle(ImportExportText.importTitle)
                    .navigationSubtitle(model.stepTitle)
                    .toolbar { toolbar }
                    .overlay {
                        if model.isWorking {
                            ProgressView(model.workingText)
                                .padding()
                                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                        }
                    }
            }
            #if os(macOS)
                // Small enough for a default-size window; the form scrolls when the steps run longer.
                .frame(
                    minWidth: 520,
                    idealWidth: 600,
                    maxWidth: .infinity,
                    minHeight: 320,
                    idealHeight: 420,
                    maxHeight: .infinity,
                )
            #endif
            // Nothing is saved before Import, but the user's column and match choices would be lost.
            .interactiveDismissDisabled(model.step != .summary)
            // A tapped reminder closes the sheet first only when nothing would be lost (S33).
            .openSheet(hasUnsavedEdits: { model.hasUnsavedEdits }, close: { dismiss() })
            .alert(
                model.alert?.title ?? "",
                isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
                presenting: model.alert,
            ) { _ in
                Button(ImportExportText.okay) {}
            } message: { alert in
                Text(alert.message)
            }
            // D281: a confirmation dialog on iOS; SwiftUI shows the same dialog as an alert on the Mac.
            .confirmationDialog(model.undoTitle, isPresented: $model.isConfirmingUndo, titleVisibility: .visible) {
                Button(ImportExportText.remove, role: .destructive) { model.undo() }
                Button(ImportExportText.cancel, role: .cancel) {}
            } message: {
                Text(model.undoMessage)
            }
            .onAppear { model.announce = { AccessibilityNotification.Announcement($0).post() } }
            .onChange(of: feature.ledgerRevision) {
                Task { await model.dataChanged() }
            }
            .onDisappear { model.close() }
        }

        /// Match and Review list a row per name or per file row, so they're a `List`, which lays out only the
        /// rows on screen, with or without VoiceOver or another accessibility client. A grouped `Form` lays out
        /// every row on the Mac, which hung a 5,200-row file (Tester's Mac pass on #190). The short steps stay a
        /// grouped `Form`.
        @ViewBuilder
        private var stepContainer: some View {
            switch model.step {
            case .match, .review:
                List { stepContent }
            case .pickFile, .columns, .account, .summary:
                Form { stepContent }
                    .formStyle(.grouped)
            }
        }

        @ViewBuilder
        private var stepContent: some View {
            // D327.1: one line of secondary footnote text, the first thing under the step's name. Text only, not
            // an alert or a banner; VoiceOver hears it once, through `model.announce`.
            if let notice = model.dataChangedNotice {
                Section {
                } footer: {
                    Text(notice)
                }
            }
            switch model.step {
            case .pickFile, .columns: CSVColumnsStep(model: model)
            case .account: CSVAccountStep(model: model)
            case .match: CSVMatchStep(model: model)
            case .review: CSVReviewStep(model: model)
            case .summary: CSVSummaryStep(model: model)
            }
        }

        #if os(iOS)
            /// iOS Cancel in `.topBarLeading`, after Back: it keeps the cancel role and Escape that
            /// `.cancellationAction` gave it. Off while “Importing…” shows, so the sheet can't close mid-save (NB2
            /// on #190).
            private var cancelButton: some View {
                Button(ImportExportText.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
            }
        #endif

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            if model.step == .summary {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ImportExportText.done) { dismiss() }
                }
            } else {
                #if os(iOS)
                    // Leading, in this order: ‹ Back, then Cancel (UI Designer, 26 Oct). Back is a plain button with
                    // the system chevron, since the steps swap in one view rather than being pushed (a
                    // NavigationStack push is #217). Both are .topBarLeading so the order is the declaration order;
                    // Cancel keeps its cancel role and Escape. They fit beside the title and Next or Import on a
                    // 375 pt iPhone SE or mini.
                    if model.canGoBack {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                model.back()
                            } label: {
                                Label(ImportExportText.back, systemImage: "chevron.left")
                                    .labelStyle(.titleAndIcon)
                            }
                            .disabled(model.isWorking)
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        cancelButton
                    }
                #else
                    ToolbarItem(placement: .cancellationAction) {
                        // Off while “Importing…” shows, so the sheet can't close mid-save (NB2 on #190).
                        Button(ImportExportText.cancel) { dismiss() }
                            .disabled(model.isWorking)
                    }
                    if model.canGoBack {
                        ToolbarItem(placement: .navigation) {
                            Button(ImportExportText.back) { model.back() }
                                .disabled(model.isWorking)
                        }
                    }
                #endif
                // Review's one Import is here, so it's reachable however long the page is and Return imports on
                // the Mac: “Import” on iOS, “Import N Transactions” as the Mac sheet's default (UI Designer, 26 Oct).
                ToolbarItem(placement: .confirmationAction) {
                    if model.step == .review {
                        Button(model.importActionTitle(on: .current)) { Task { await model.commit() } }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!model.canImport)
                    } else {
                        Button(ImportExportText.next) { Task { await model.next() } }
                            .disabled(!model.canGoNext || model.isWorking)
                    }
                }
            }
        }
    }

    // MARK: Columns

    private struct CSVColumnsStep: View {
        @Bindable var model: CSVImportViewModel

        var body: some View {
            Section {
                Text(model.fileSummary)
                    .foregroundStyle(.secondary)
            } footer: {
                if let note = model.formatNote {
                    Label(note, systemImage: "info.circle")
                }
            }
            Section {
                ForEach(model.columnRows) { column in
                    Picker(selection: fieldBinding(column)) {
                        Text(ImportExportText.notImported).tag(ImportField?.none)
                        ForEach(ImportField.allCases, id: \.self) { field in
                            Text(ImportExportText.field(field)).tag(ImportField?.some(field))
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(column.header)
                            if !column.samples.isEmpty {
                                Text(column.samples)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } header: {
                Text(ImportExportText.columnsHeader)
            } footer: {
                Text(model.canContinueFromColumns ? ImportExportText.columnsFooter : ImportExportText.amountRequired)
            }
            if model.showsReadFormat {
                readFormat
            }
            Section(ImportExportText.previewHeader) {
                ForEach(Array(model.previewLines.enumerated()), id: \.offset) { _, line in
                    LabeledContent(line.row, value: line.text)
                }
            }
        }

        /// The date format and decimal separator; a preset's layout is fixed, so it hides them.
        @ViewBuilder
        private var readFormat: some View {
            Section {
                if model.showsDateOrder {
                    Picker(ImportExportText.dateFormat, selection: $model.dateOrder) {
                        ForEach(model.dateOrderChoices, id: \.self) { order in
                            Text(dateOrderLabel(order)).tag(order)
                        }
                    }
                }
                Picker(ImportExportText.decimalSeparator, selection: $model.decimalSeparator) {
                    ForEach(ImportDecimalSeparator.allCases, id: \.self) { separator in
                        Text(ImportExportText.separator(separator)).tag(separator)
                    }
                }
            } header: {
                Text(ImportExportText.formatHeader)
            } footer: {
                if model.hasAmbiguousDates {
                    Text(ImportExportText.ambiguousDates)
                }
            }
            // Off during “Reading…”: a Mac menu pick applies a moment after the click, so it could land after the
            // plan moved the sheet on (#232).
            .disabled(model.isPlanning)
        }

        private func fieldBinding(_ column: ImportColumnRow) -> Binding<ImportField?> {
            Binding(get: { column.field }, set: { model.setField($0, forColumn: column.id) })
        }

        /// “DD/MM/YYYY · Detected” for the order the file's dates point to.
        private func dateOrderLabel(_ order: ImportDateOrder) -> String {
            let name = ImportExportText.dateOrder(order)
            guard model.detection?.date.order == order else {
                return name
            }
            return ImportExportText.detectedFormat(name)
        }
    }

    // MARK: Account

    private struct CSVAccountStep: View {
        @Bindable var model: CSVImportViewModel

        var body: some View {
            Section {
                Picker(ImportExportText.accountQuestion, selection: $model.targetAccountID) {
                    ForEach(model.accountOptions) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
                .pickerStyle(.inline)
                // The section header asks the question; the picker keeps it as its accessibility label.
                .labelsHidden()
            } header: {
                Text(ImportExportText.accountQuestion)
            } footer: {
                Text(ImportExportText.accountFooter)
            }
        }
    }

    // MARK: Match

    private struct CSVMatchStep: View {
        let model: CSVImportViewModel

        var body: some View {
            accountsSection
            matchSection(ImportExportText.matchCategories, model.categoryMatches)
            matchSection(ImportExportText.matchPayees, model.payeeMatches)
            Section {
            } footer: {
                Text(ImportExportText.matchFooter)
            }
        }

        /// Accounts, with a currency picker under each new one when the file has no currency column (#60).
        @ViewBuilder
        private var accountsSection: some View {
            let rows = model.accountMatches
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        choicePicker(row)
                        if let code = row.newAccountCurrency {
                            Picker(ImportExportText.field(.currency), selection: currencyBinding(row, code)) {
                                ForEach(model.currencyOptions, id: \.self) { option in
                                    Text(model.currencyTitle(for: option)).tag(option)
                                }
                            }
                        }
                    }
                } header: {
                    VStack(alignment: .leading) {
                        Text(ImportExportText.matchAccounts)
                        if let note = model.accountsHeaderNote {
                            Text(note)
                                .textCase(nil)
                        }
                    }
                } footer: {
                    if let note = model.accountsFooterNote {
                        Label(note, systemImage: "exclamationmark.circle")
                    }
                }
            }
        }

        private func currencyBinding(_ row: ImportMatchRow, _ code: String) -> Binding<String> {
            Binding(
                get: { code },
                set: { newCode in Task { await model.setCurrency(newCode, forNewAccount: row.id) } },
            )
        }

        @ViewBuilder
        private func matchSection(_ title: String, _ rows: [ImportMatchRow]) -> some View {
            if !rows.isEmpty {
                Section(title) {
                    ForEach(rows) { row in
                        choicePicker(row)
                    }
                }
            }
        }

        /// The name, with its row count beneath as the label's subtitle when there is one (#60).
        private func choicePicker(_ row: ImportMatchRow) -> some View {
            Picker(selection: choiceBinding(row)) {
                Text(ImportExportText.createNew).tag(ImportMatchChoice.new)
                ForEach(row.options) { option in
                    Text(option.name).tag(ImportMatchChoice.existing(option.id))
                }
            } label: {
                Text(row.name)
                if let detail = row.detail {
                    Text(detail)
                }
            }
        }

        private func choiceBinding(_ row: ImportMatchRow) -> Binding<ImportMatchChoice> {
            Binding(
                get: { row.choice },
                set: { choice in Task { await model.setChoice(choice, for: row.id) } },
            )
        }
    }

    // MARK: Review

    private struct CSVReviewStep: View {
        let model: CSVImportViewModel

        var body: some View {
            Section {
                LabeledContent(ImportExportText.toImport, value: model.readyCount.formatted())
                LabeledContent(ImportExportText.cantImport, value: model.failedCount.formatted())
                LabeledContent(ImportExportText.shortened, value: model.shortenedCount.formatted())
                LabeledContent(ImportExportText.alreadyImported, value: model.alreadyImportedCount.formatted())
                LabeledContent(ImportExportText.possibleDuplicates, value: model.possibleDuplicateCount.formatted())
            } footer: {
                Text(model.reviewFooter(on: .current))
            }
            if model.isDebitAndCredit {
                debitAndCreditPreview
            }
            rows(ImportExportText.toImportSection, model.selectedRows, selected: true)
            if !model.unselectedRows.isEmpty {
                Section {
                    ForEach(model.unselectedRows) { row in
                        ImportReviewRowView(row: row, isSelected: false) { model.toggle(row.id) }
                    }
                } header: {
                    Text(ImportExportText.notSelected)
                } footer: {
                    Text(model.notSelectedFooter)
                }
            }
            rows(ImportExportText.cantImportSection, model.failedRows, selected: false)
        }

        /// What the ticked rows create, and their totals per account (#60 “Preview”).
        @ViewBuilder
        private var debitAndCreditPreview: some View {
            let created = model.createdCounts
            Section(ImportExportText.willBeCreated) {
                LabeledContent(ImportExportText.newAccounts, value: created.accounts.formatted())
                LabeledContent(ImportExportText.newCategories, value: created.categories.formatted())
                LabeledContent(ImportExportText.newPayees, value: created.payees.formatted())
            }
            let totals = model.accountTotals
            if !totals.isEmpty {
                Section {
                    ForEach(totals) { total in
                        VStack(alignment: .leading) {
                            LabeledContent(total.name, value: total.currencyCode)
                            LabeledContent(ImportExportText.income, value: total.income)
                            LabeledContent(ImportExportText.expense, value: total.expense)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text(ImportExportText.totalsByAccount)
                } footer: {
                    Text(ImportExportText.totalsFooter)
                }
            }
        }

        @ViewBuilder
        private func rows(_ title: String, _ rows: [ImportReviewRow], selected: Bool) -> some View {
            if !rows.isEmpty {
                Section(title) {
                    ForEach(rows) { row in
                        ImportReviewRowView(row: row, isSelected: selected) { model.toggle(row.id) }
                    }
                }
            }
        }
    }

    private struct ImportReviewRowView: View {
        let row: ImportReviewRow
        let isSelected: Bool
        let toggle: () -> Void

        var body: some View {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline) {
                    if row.isSelectable {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Every reason on its own line when the format lists them all (D110).
                        ForEach(Array(row.reasons.enumerated()), id: \.offset) { _, reason in
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(messageColor)
                        }
                        if let source = row.source {
                            // D349.1: a long value is cut at the end by the system, not by the text.
                            Text(verbatim: source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer()
                    Text(row.amount)
                        .monospacedDigit()
                        .foregroundStyle(row.tone.color)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!row.isSelectable)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private var messageColor: AnyShapeStyle {
            switch row.messageStyle {
            case .secondary: AnyShapeStyle(.secondary)
            case .warning: AnyShapeStyle(Color.orange)
            case .error: AnyShapeStyle(Color.red)
            }
        }
    }
#endif

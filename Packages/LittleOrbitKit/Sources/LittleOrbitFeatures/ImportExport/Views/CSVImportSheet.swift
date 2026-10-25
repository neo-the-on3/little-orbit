#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// The import sheet: Columns, the target account when the file names none, Match, Review and the summary.
    /// Standard grouped forms and controls; all logic is in `CSVImportViewModel`.
    struct CSVImportSheet: View {
        @Bindable var model: CSVImportViewModel
        /// For the shared store-change signal (D327.1).
        let feature: ImportExportFeature
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    // D327.1: one line of secondary footnote text, the first thing under the step's name. Text
                    // only, not an alert or a banner; VoiceOver hears it once, through `model.announce`.
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
                .formStyle(.grouped)
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

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            if model.step == .summary {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ImportExportText.done) { dismiss() }
                }
            } else {
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
                // Review saves with its own “Import N Transactions” button at the end of the page, so there's one
                // Import button, not a second one here (Tester's #190 Mac pass).
                if model.step != .review {
                    ToolbarItem(placement: .confirmationAction) {
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
            Section {
                Picker(ImportExportText.dateFormat, selection: $model.dateOrder) {
                    ForEach(model.dateOrderChoices, id: \.self) { order in
                        Text(dateOrderLabel(order)).tag(order)
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
            Section(ImportExportText.previewHeader) {
                ForEach(Array(model.previewLines.enumerated()), id: \.offset) { _, line in
                    LabeledContent(line.row, value: line.text)
                }
            }
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
            matchSection(ImportExportText.matchAccounts, model.accountMatches)
            matchSection(ImportExportText.matchCategories, model.categoryMatches)
            matchSection(ImportExportText.matchPayees, model.payeeMatches)
            Section {
            } footer: {
                Text(ImportExportText.matchFooter)
            }
        }

        @ViewBuilder
        private func matchSection(_ title: String, _ rows: [ImportMatchRow]) -> some View {
            if !rows.isEmpty {
                Section(title) {
                    ForEach(rows) { row in
                        Picker(row.name, selection: choiceBinding(row)) {
                            Text(ImportExportText.createNew).tag(ImportMatchChoice.new)
                            ForEach(row.options) { option in
                                Text(option.name).tag(ImportMatchChoice.existing(option.id))
                            }
                        }
                    }
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
                    Text(ImportExportText.notSelectedFooter)
                }
            }
            rows(ImportExportText.cantImportSection, model.failedRows, selected: false)
            Section {
                Button(model.importTitle) { Task { await model.commit() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canImport)
            } footer: {
                Text(model.reviewFooter(on: .current))
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
                        if let message = row.message {
                            Text(message)
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

    // MARK: Summary

    private struct CSVSummaryStep: View {
        let model: CSVImportViewModel

        /// “Undo Import…” on the Mac, because it asks first (D281); “Undo Import” on iOS.
        private var undoLabel: String {
            #if os(macOS)
                ImportExportText.undoImportEllipsis
            #else
                ImportExportText.undoImport
            #endif
        }

        var body: some View {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: model.isUndone ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(model.summaryTitle)
                        .font(.title2.bold())
                    Text(model.importedText)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            if !model.createdLines.isEmpty {
                Section(ImportExportText.alsoCreated) {
                    ForEach(model.createdLines, id: \.self) { line in
                        Text(line)
                    }
                }
            }
            if !model.notImportedLines.isEmpty {
                Section(ImportExportText.rowsNotImported) {
                    ForEach(model.notImportedLines, id: \.label) { line in
                        LabeledContent(line.label, value: line.count.formatted())
                    }
                }
            }
            if let note = model.unlinkedRefundNote {
                Section {
                    Text(note)
                }
            }
            if model.canUndo {
                Section {
                    Button(undoLabel, role: .destructive) { model.requestUndo() }
                } footer: {
                    Text(ImportExportText.undoFooter)
                }
            }
        }
    }
#endif

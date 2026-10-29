#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// The Review step: the counts, #60's preview, and the rows to import, not selected and that can't import.
    struct CSVReviewStep: View {
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

    struct ImportReviewRowView: View {
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

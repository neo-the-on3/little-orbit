#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// The Columns step: each column's field, the date format and decimal separator, and the first rows.
    struct CSVColumnsStep: View {
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
#endif

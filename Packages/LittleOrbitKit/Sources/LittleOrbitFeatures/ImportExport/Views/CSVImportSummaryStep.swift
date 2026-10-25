#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// The import sheet's last step: what was imported, what wasn't, and Undo Import.
    struct CSVSummaryStep: View {
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

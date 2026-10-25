#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// The export sheet: which transactions, the date range and date style, then the system save panel.
    struct CSVExportSheet: View {
        @State private var model: CSVExportViewModel
        @Environment(\.dismiss) private var dismiss

        init(feature: ImportExportFeature) {
            _model = State(initialValue: feature.makeExport())
        }

        /// “Export…” on the Mac, where a save panel follows; “Export” on iOS (D190, D323.13).
        private var exportLabel: String {
            #if os(macOS)
                ImportExportText.exportEllipsis
            #else
                ImportExportText.export
            #endif
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section(ImportExportText.transactions) {
                        Picker(ImportExportText.transactions, selection: $model.scope) {
                            Text(ImportExportText.allTransactions).tag(CSVExportViewModel.Scope.all)
                            Text(ImportExportText.someAccounts).tag(CSVExportViewModel.Scope.accounts)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        if model.scope == .accounts {
                            ForEach(model.accounts) { account in
                                Toggle(account.name, isOn: accountBinding(account.id))
                            }
                        }
                    }
                    Section {
                        Picker(ImportExportText.dateRange, selection: $model.range) {
                            Text(ImportExportText.allTime).tag(CSVExportViewModel.Range.allTime)
                            Text(ImportExportText.thisMonth).tag(CSVExportViewModel.Range.thisMonth)
                            Text(ImportExportText.custom).tag(CSVExportViewModel.Range.custom)
                        }
                        if model.range == .custom {
                            DatePicker(
                                ImportExportText.from,
                                selection: $model.customStart,
                                displayedComponents: .date,
                            )
                            DatePicker(
                                ImportExportText.through,
                                selection: $model.customEnd,
                                displayedComponents: .date,
                            )
                        }
                    }
                    Section {
                        Toggle(ImportExportText.isoDates, isOn: $model.iso8601Dates)
                    } footer: {
                        Text(ImportExportText.formatFooter)
                    }
                    Section {
                        Text(model.countText)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(ImportExportText.exportTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ImportExportText.cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(exportLabel) { model.export() }
                            .disabled(!model.canExport)
                    }
                }
            }
            #if os(macOS)
                // No taller than a default-size window; the form scrolls when the account list runs longer
                // (Tester's #190 Mac pass: the sheet ran past the window's bottom edge).
                .frame(
                    minWidth: 460,
                    idealWidth: 520,
                    maxWidth: .infinity,
                    minHeight: 300,
                    idealHeight: 400,
                    maxHeight: .infinity,
                )
            #endif
            .task { model.load() }
            .fileExporter(
                isPresented: $model.isExporterPresented,
                document: model.pendingFile.map { CSVFileDocument(data: $0.data) },
                contentTypes: [.commaSeparatedText],
                defaultFilename: model.defaultFileName,
                onCompletion: { result in
                    switch result {
                    case .success:
                        model.exportFinished(saved: true, failed: false)
                        dismiss()
                    case .failure:
                        model.exportFinished(saved: false, failed: true)
                    }
                },
                onCancellation: { model.exportFinished(saved: false, failed: false) },
            )
            .alert(
                model.alert?.title ?? "",
                isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
                presenting: model.alert,
            ) { _ in
                ImportAlertOKButton()
            } message: { alert in
                Text(alert.message)
            }
        }

        private func accountBinding(_ id: UUID) -> Binding<Bool> {
            Binding(get: { model.selectedAccountIDs.contains(id) }, set: { _ in model.toggleAccount(id) })
        }
    }
#endif

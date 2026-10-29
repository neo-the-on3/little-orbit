#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// The Match step: each account, category and payee name in the file and what it's matched to.
    struct CSVMatchStep: View {
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
#endif

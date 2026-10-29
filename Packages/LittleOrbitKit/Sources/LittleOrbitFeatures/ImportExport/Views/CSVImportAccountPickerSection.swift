#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// The Account step: which account the file is for, when it names none.
    struct CSVImportAccountPickerSection: View {
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
#endif

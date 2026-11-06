#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// The Account step: which account the file is for, when it names none.
    struct CSVImportAccountPickerSection: View {
        @Bindable var model: CSVImportViewModel
        @State private var showsNewAccount = false

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
                Button(ImportExportText.newAccountAction) { showsNewAccount = true }
                    .sheet(isPresented: $showsNewAccount) {
                        AccountFormView(model: model.newAccountForm()) { model.selectNewAccount($0) }
                    }
            } header: {
                Text(ImportExportText.accountQuestion)
            } footer: {
                Text(ImportExportText.accountFooter)
            }
        }
    }
#endif

#if canImport(SwiftUI) && os(iOS)
    import SwiftUI

    /// iOS Settings › Import & Export (#30): import a CSV file from Files, or export transactions to one.
    struct ImportExportSettingsView: View {
        let feature: ImportExportFeature
        @State private var isPicking = false
        @State private var isExporting = false

        var body: some View {
            List {
                Section {
                    Button {
                        isPicking = true
                    } label: {
                        Label(ImportExportText.importRow, systemImage: "square.and.arrow.down")
                    }
                    .disabled(!feature.importEnabled)
                    Button {
                        isExporting = true
                    } label: {
                        Label(ImportExportText.exportRow, systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text(ImportExportText.sectionFooter)
                }
            }
            .navigationTitle(ImportExportText.sectionTitle)
            .modifier(CSVImportModifier(feature: feature, isPicking: $isPicking))
            .sheet(isPresented: $isExporting) {
                CSVExportSheet(feature: feature)
            }
        }
    }
#endif

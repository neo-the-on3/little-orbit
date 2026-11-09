#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import CoreTransferable
    import LittleOrbitDomain
    import SwiftUI
    import UniformTypeIdentifiers

    /// What Share… hands the share sheet (#189 E3): the file Export would write, made only when the share sheet asks
    /// for it, as `.tsv` for Tab and `.csv` otherwise.
    struct CSVExportShareItem: Transferable, Sendable {
        let delimiter: CSVDelimiter
        let make: @MainActor @Sendable () throws -> TransactionExport

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(exportedContentType: .tabSeparatedText) { item in
                SentTransferredFile(try await item.writtenFile())
            }
            .exportingCondition { $0.delimiter == .tab }
            FileRepresentation(exportedContentType: .commaSeparatedText) { item in
                SentTransferredFile(try await item.writtenFile())
            }
            .exportingCondition { $0.delimiter != .tab }
        }

        private func writtenFile() async throws -> URL {
            try CSVShareFile.write(try await make())
        }
    }

    /// “Share…”: a ShareLink beside Export on iOS, and at the leading edge of the Mac sheet's buttons (#189 E3).
    struct CSVExportShareLink: View {
        let model: CSVExportViewModel

        var body: some View {
            ShareLink(
                ImportExportText.share,
                item: CSVExportShareItem(delimiter: model.delimiter) { [model] in try model.shareFile() },
                preview: SharePreview(model.shareFileName),
            )
            .disabled(!model.canExport)
        }
    }
#endif

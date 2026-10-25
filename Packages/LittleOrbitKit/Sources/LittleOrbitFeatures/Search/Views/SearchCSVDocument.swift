#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI
    import UniformTypeIdentifiers

    /// Search's exported CSV file (#187), for the system save panel or Files. The bytes come from
    /// `TransactionCSVWriter` through the export use case; this only hands them to the exporter. It matches the
    /// CSV import and export screens' `CSVFileDocument` (#30), which isn't on this branch yet; once both are in,
    /// search uses that one and this file goes.
    struct SearchCSVDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.commaSeparatedText] }

        let data: Data

        init(data: Data) {
            self.data = data
        }

        init(configuration: ReadConfiguration) throws {
            data = configuration.file.regularFileContents ?? Data()
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }
#endif

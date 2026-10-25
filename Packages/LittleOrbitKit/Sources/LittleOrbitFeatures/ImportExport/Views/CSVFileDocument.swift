#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI
    import UniformTypeIdentifiers

    /// An exported CSV file's bytes, for the system save panel or Files.
    struct CSVFileDocument: FileDocument {
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

    /// The file types the import picker offers: CSV, tab-separated and plain text.
    enum CSVImportTypes {
        static let all: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText]
    }
#endif

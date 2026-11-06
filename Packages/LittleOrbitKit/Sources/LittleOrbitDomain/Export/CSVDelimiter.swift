import Foundation

/// The character between an export's fields (#189 E1, D387.8). Comma is the default. Every choice writes the same
/// columns, CRLF line ends and UTF-8 with a byte order mark; only the separator, the quoting it needs and the file
/// extension change. There is no encoding choice (D387.8).
public enum CSVDelimiter: String, CaseIterable, Hashable, Sendable {
    case comma
    case semicolon
    case tab

    /// The separator written between fields.
    public var character: Character {
        switch self {
        case .comma: ","
        case .semicolon: ";"
        case .tab: "\t"
        }
    }

    /// `tsv` for Tab, `csv` otherwise (D387.8).
    public var fileExtension: String {
        self == .tab ? "tsv" : "csv"
    }

    /// The file's uniform type identifier, for the save panel and the share sheet. A semicolon file is still a CSV
    /// file to Numbers and Excel.
    public var contentTypeIdentifier: String {
        self == .tab ? "public.tab-separated-values-text" : "public.comma-separated-values-text"
    }
}

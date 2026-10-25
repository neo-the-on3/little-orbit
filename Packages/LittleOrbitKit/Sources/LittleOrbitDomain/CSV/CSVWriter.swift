import Foundation

/// An RFC 4180 writer: comma-separated fields, CRLF after every record, and a field in double quotes when it
/// holds a comma, a quote, a line break or leading or trailing spaces, with each quote doubled. Values go out
/// exactly as given, so names with emoji, Hindi text or quotes round-trip through `CSVReader` (#30 S28).
public enum CSVWriter {
    public static let lineEnding = "\r\n"
    /// The UTF-8 byte order mark, so Numbers and Excel read the file as UTF-8 (#30 PM answer 4).
    public static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// One field, quoted when it has to be.
    public static func field(_ value: String, delimiter: Character = ",") -> String {
        let needsQuotes =
            value.contains(delimiter) || value.contains("\"") || value.contains("\n") || value.contains("\r")
            || value.first?.isWhitespace == true || value.last?.isWhitespace == true
        guard needsQuotes else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The records as CSV text, each ending in CRLF.
    public static func text(_ records: [[String]], delimiter: Character = ",") -> String {
        var text = ""
        for record in records {
            text += record.map { field($0, delimiter: delimiter) }.joined(separator: String(delimiter))
            text += lineEnding
        }
        return text
    }

    /// The records as UTF-8 bytes with a byte order mark.
    public static func data(_ records: [[String]], delimiter: Character = ",") -> Data {
        Data(byteOrderMark) + Data(text(records, delimiter: delimiter).utf8)
    }
}

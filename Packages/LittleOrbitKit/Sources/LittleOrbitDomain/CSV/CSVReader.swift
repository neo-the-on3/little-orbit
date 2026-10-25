import Foundation

/// Why a picked file can't be read as CSV at all. Nothing is imported in either case (#30 S33, S34).
public enum CSVFileError: Error, Equatable, Sendable {
    /// A 0-byte file, or one with nothing but a byte order mark and blank lines.
    case empty
    /// Not text: a spreadsheet or archive renamed to `.csv`, or bytes no supported encoding reads.
    case notText
}

/// One record of a CSV file. `rowNumber` counts records the way a spreadsheet shows rows: the header is row 1
/// and the first data row is row 2. A quoted field with line breaks inside it is still one row (D43).
public struct CSVRecord: Equatable, Sendable {
    public var rowNumber: Int
    public var fields: [String]
    /// The file ended inside this record's quoted field, so its last field ran to the end of the file.
    public var isUnterminated: Bool

    public init(rowNumber: Int, fields: [String], isUnterminated: Bool = false) {
        self.rowNumber = rowNumber
        self.fields = fields
        self.isUnterminated = isUnterminated
    }

    /// The field at `index`, or `nil` when the record is shorter.
    public func field(_ index: Int) -> String? {
        fields.indices.contains(index) ? fields[index] : nil
    }
}

/// A decoded CSV file: its header and its data records. Blank records are left out, but they still count
/// towards the row numbers of the records after them.
public struct CSVTable: Equatable, Sendable {
    public var delimiter: Character
    public var header: [String]
    public var records: [CSVRecord]

    public init(delimiter: Character, header: [String], records: [CSVRecord]) {
        self.delimiter = delimiter
        self.header = header
        self.records = records
    }
}

/// Turns a file's bytes into text: UTF-8 with or without a byte order mark, UTF-16 with a byte order mark
/// or with the zero bytes that give it away, and Windows-1252 for older bank exports. Archives, PDFs and other
/// binary files are refused (#30 S34).
public enum CSVText {
    public static func decode(_ data: Data) throws -> String {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else {
            throw CSVFileError.empty
        }
        let text = try decodedText(bytes)
        let content = text.unicodeScalars.filter { $0 != "\u{FEFF}" }
        guard content.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }) else {
            throw CSVFileError.empty
        }
        // Control characters other than tab and line breaks don't appear in a text table.
        let controls = content.filter { $0.value < 0x20 && $0 != "\t" && $0 != "\n" && $0 != "\r" }.count
        if controls > 0 && controls * 100 >= content.count {
            throw CSVFileError.notText
        }
        return String(String.UnicodeScalarView(content))
    }

    private static func decodedText(_ bytes: [UInt8]) throws -> String {
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) || bytes.starts(with: [0x25, 0x50, 0x44, 0x46])
            || bytes.starts(with: [0xD0, 0xCF, 0x11, 0xE0])
        {
            // ZIP (XLSX, Numbers), PDF and the old binary Excel format.
            throw CSVFileError.notText
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return try utf8(Array(bytes.dropFirst(3)))
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return try decode(Array(bytes.dropFirst(2)), .utf16LittleEndian)
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return try decode(Array(bytes.dropFirst(2)), .utf16BigEndian)
        }
        if bytes.contains(0) {
            let sample = bytes.prefix(512)
            let evenZeros = stride(from: 0, to: sample.count, by: 2).filter { sample[$0] == 0 }.count
            let oddZeros = stride(from: 1, to: sample.count, by: 2).filter { sample[$0] == 0 }.count
            let half = sample.count / 2
            if oddZeros * 10 >= half * 9 && evenZeros == 0 {
                return try decode(bytes, .utf16LittleEndian)
            }
            if evenZeros * 10 >= half * 9 && oddZeros == 0 {
                return try decode(bytes, .utf16BigEndian)
            }
            throw CSVFileError.notText
        }
        if let text = String(validating: bytes, as: UTF8.self) {
            return text
        }
        return try decode(bytes, .windowsCP1252)
    }

    private static func utf8(_ bytes: [UInt8]) throws -> String {
        guard let text = String(validating: bytes, as: UTF8.self) else {
            throw CSVFileError.notText
        }
        return text
    }

    private static func decode(_ bytes: [UInt8], _ encoding: String.Encoding) throws -> String {
        guard let text = String(data: Data(bytes), encoding: encoding) else {
            throw CSVFileError.notText
        }
        return text
    }
}

/// An RFC 4180 reader. Fields are separated by the delimiter and records by CRLF, LF or CR. A field that
/// starts with a double quote runs to the matching closing quote, so it may hold delimiters and line breaks,
/// and `""` inside it is one quote. Quotes inside an unquoted field are kept as they are, and so is anything
/// between a closing quote and the next delimiter, so a sloppy file still reads instead of failing whole.
public enum CSVReader {
    /// The candidate delimiters, most likely first: comma, semicolon (European exports), tab and pipe.
    public static let delimiters: [Character] = [",", ";", "\t", "|"]

    /// Reads `text` into a table. With no `delimiter`, the one used most in the first record wins.
    public static func read(_ text: String, delimiter: Character? = nil) throws -> CSVTable {
        let scalars = Array(text.unicodeScalars)
        let separator = delimiter ?? detectDelimiter(scalars)
        let records = parse(scalars, delimiter: separator.unicodeScalars.first ?? ",")
        guard let headerIndex = records.firstIndex(where: { !isBlank($0) }) else {
            throw CSVFileError.empty
        }
        let header = records[headerIndex].fields
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
            }
        let rows = records[(headerIndex + 1)...].filter { !isBlank($0) }
        return CSVTable(delimiter: separator, header: header, records: Array(rows))
    }

    static func isBlank(_ record: CSVRecord) -> Bool {
        !record.isUnterminated
            && record.fields.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The candidate that appears most often outside quotes in the first non-blank line; comma on a tie or
    /// when there's none, as in a one-column file.
    static func detectDelimiter(_ scalars: [Unicode.Scalar]) -> Character {
        var counts: [Unicode.Scalar: Int] = [:]
        var inQuotes = false
        var seenContent = false
        for scalar in scalars {
            if scalar == "\"" {
                inQuotes.toggle()
            } else if !inQuotes && (scalar == "\n" || scalar == "\r") {
                if seenContent {
                    break
                }
            } else if !inQuotes {
                if !CharacterSet.whitespaces.contains(scalar) && scalar != "\u{FEFF}" {
                    seenContent = true
                }
                counts[scalar, default: 0] += 1
            }
        }
        var best: Character = ","
        var bestCount = 0
        for candidate in delimiters {
            let count = counts[candidate.unicodeScalars.first!] ?? 0
            if count > bestCount {
                best = candidate
                bestCount = count
            }
        }
        return best
    }

    // One RFC 4180 state machine reads best as a single loop.
    // swiftlint:disable:next cyclomatic_complexity
    private static func parse(_ scalars: [Unicode.Scalar], delimiter: Unicode.Scalar) -> [CSVRecord] {
        var records: [CSVRecord] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var index = 0
        var rowNumber = 1
        var atFieldStart = true
        var inQuotes = false
        var recordHasContent = false

        func endField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
            atFieldStart = true
        }
        func endRecord(unterminated: Bool = false) {
            endField()
            records.append(CSVRecord(rowNumber: rowNumber, fields: fields, isUnterminated: unterminated))
            fields = []
            rowNumber += 1
            recordHasContent = false
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count && scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(scalar)
                }
                index += 1
                continue
            }
            switch scalar {
            case "\"" where atFieldStart:
                inQuotes = true
                atFieldStart = false
                recordHasContent = true
            case delimiter:
                endField()
                recordHasContent = true
            case "\r", "\n":
                endRecord()
                if scalar == "\r" && index + 1 < scalars.count && scalars[index + 1] == "\n" {
                    index += 1
                }
            default:
                field.append(scalar)
                atFieldStart = false
                recordHasContent = true
            }
            index += 1
        }
        if inQuotes {
            endRecord(unterminated: true)
        } else if recordHasContent || !field.isEmpty {
            endRecord()
        }
        return records
    }
}

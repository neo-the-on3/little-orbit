import Foundation
import LittleOrbitDomain
import Testing

/// The hand-written RFC 4180 reader and the file decoding in front of it (#30 AC 1, S7–S9, S24, S26).
@Suite("CSV reader (#30)")
struct CSVReaderTests {
    @Test("Quoted fields keep commas, doubled quotes and line breaks")
    func quoting() throws {
        let table = try CSVReader.read(
            "Date,Description\r\n2026-10-20,\"Tea, “masala”\"\r\n2026-10-21,\"He said \"\"hi\"\"\nthen left\"\r\n"
        )
        #expect(table.header == ["Date", "Description"])
        #expect(
            table.records.map(\.fields) == [
                ["2026-10-20", "Tea, “masala”"],
                ["2026-10-21", "He said \"hi\"\nthen left"],
            ]
        )
    }

    @Test("Row numbers count the header and skipped blank lines, as a spreadsheet does")
    func rowNumbers() throws {
        let table = try CSVReader.read("Date,Amount\n2026-10-20,5\n\n2026-10-21,6\n")
        #expect(table.records.map(\.rowNumber) == [2, 4])
    }

    @Test("CR CR LF between records is one line break: no blank records, and the row numbers don't shift")
    func doubledCarriageReturn() throws {
        let table = try CSVReader.read("Date,Amount\r\r\n2026-10-20,5\r\r\n2026-10-21,6\r\r\n\r\r\n2026-10-22,7")
        #expect(table.header == ["Date", "Amount"])
        #expect(table.records.map(\.fields) == [["2026-10-20", "5"], ["2026-10-21", "6"], ["2026-10-22", "7"]])
        // The blank line before the last record still counts, as in a spreadsheet.
        #expect(table.records.map(\.rowNumber) == [2, 3, 5])
    }

    @Test("A quote left open to the end is flagged on its row")
    func unterminated() throws {
        let table = try CSVReader.read("Date,Description\n2026-10-20,\"open\n")
        #expect(table.records.last?.isUnterminated == true)
    }

    @Test("The delimiter is detected among comma, semicolon, tab and bar", arguments: [",", ";", "\t", "|"])
    func delimiters(delimiter: String) throws {
        let text =
            ["Date", "Amount", "Payee"].joined(separator: delimiter) + "\n"
            + ["20/10/2026", "5", "Corner Shop"].joined(separator: delimiter) + "\n"
        let table = try CSVReader.read(text)
        #expect(String(table.delimiter) == delimiter)
        #expect(table.records.first?.fields == ["20/10/2026", "5", "Corner Shop"])
    }

    @Test("A header-only or empty file is empty")
    func empty() {
        #expect(throws: CSVFileError.empty) { try CSVReader.read("") }
        #expect(throws: CSVFileError.empty) { try CSVText.decode(Data()) }
    }

    @Test("UTF-8 with or without a byte order mark, and UTF-16 with one, decode to the same text")
    func encodings() throws {
        let text = "Date,Payee\n2026-10-20,Café ₹\n"
        let plain = Data(text.utf8)
        let bom = Data(CSVWriter.byteOrderMark) + plain
        var utf16 = Data([0xFF, 0xFE])
        utf16.append(text.data(using: .utf16LittleEndian) ?? Data())
        #expect(try CSVText.decode(plain) == text)
        #expect(try CSVText.decode(bom) == text)
        #expect(try CSVText.decode(utf16) == text)
    }

    @Test("Bytes that aren't UTF-8 fall back to Windows-1252")
    func windows1252() throws {
        let data = Data("Payee\nCaf".utf8) + Data([0xE9]) + Data("\n".utf8)
        #expect(try CSVText.decode(data) == "Payee\nCafé\n")
    }

    @Test("A spreadsheet or PDF picked by mistake isn't text")
    func notText() {
        #expect(throws: CSVFileError.notText) { try CSVText.decode(Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00])) }
        #expect(throws: CSVFileError.notText) { try CSVText.decode(Data("%PDF-1.7\n".utf8)) }
    }

    @Test("The writer quotes only what needs it and reads back unchanged")
    func roundTrip() throws {
        let records = [
            ["Date", "Notes"], ["2026-10-20", "Tea, “masala”"], ["2026-10-21", "a \"b\"\nc"], ["x", " padded "],
        ]
        let text = CSVWriter.text(records)
        #expect(text.hasPrefix("Date,Notes\r\n2026-10-20,\"Tea, “masala”\"\r\n"))
        let table = try CSVReader.read(text)
        #expect([table.header] + table.records.map(\.fields) == records)
        #expect(Array(CSVWriter.data(records).prefix(3)) == CSVWriter.byteOrderMark)
    }
}

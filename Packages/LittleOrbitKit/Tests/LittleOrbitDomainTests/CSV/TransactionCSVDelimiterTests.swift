import Foundation
import LittleOrbitDomain
import Testing

/// #189 E1 (D387.8): Comma, Semicolon or Tab between fields, `.tsv` for Tab, and always UTF-8 with a BOM.
@Suite("Export delimiter (#189 E1)")
@MainActor
struct TransactionCSVDelimiterTests {
    typealias F = ImportFixture  // swiftlint:disable:this type_name

    private func transactions() -> [Transaction] {
        [
            Transaction(
                type: .expense,
                amount: F.dec("450"),
                date: F.date(2026, 10, 20, 9),
                timeZoneID: F.zone,
                accountID: F.savingsID,
                categoryID: F.groceriesID,
                payeeID: F.cornerShopID,
                details: "Bread, buns; cake",
                note: "Two\tboxes",
            ),
            Transaction(
                type: .expense,
                amount: F.dec("649"),
                date: F.date(2026, 10, 21),
                timeZoneID: F.zone,
                accountID: F.savingsID,
                details: "StreamBox",
            ),
        ]
    }

    private var lookup: TransactionCSVLookup {
        TransactionCSVLookup(accounts: F.accounts(), categories: F.categories(), payees: F.payees())
    }

    private func text(_ delimiter: CSVDelimiter) -> String {
        TransactionCSVWriter.text(for: transactions(), lookup: lookup, dateStyle: .iso8601, delimiter: delimiter)
    }

    @Test("E1: the choices are Comma, Semicolon and Tab, and Comma is the default")
    func choicesAndDefault() {
        #expect(CSVDelimiter.allCases == [.comma, .semicolon, .tab])
        #expect(TransactionExportOptions().delimiter == .comma)
        #expect(CSVDelimiter.comma.character == ",")
        #expect(CSVDelimiter.semicolon.character == ";")
        #expect(CSVDelimiter.tab.character == "\t")
        let unchanged = TransactionCSVWriter.text(for: transactions(), lookup: lookup, dateStyle: .iso8601)
        #expect(text(.comma) == unchanged)
    }

    @Test("E1: each delimiter separates the fields and quotes only the cells that need it")
    func escapingPerDelimiter() {
        let comma = text(.comma).components(separatedBy: "\r\n")
        #expect(comma[0].hasPrefix("Date,Type,Account,To Account,Amount"))
        #expect(comma[1].contains(",\"Bread, buns; cake\",Two\tboxes"))

        let semicolon = text(.semicolon).components(separatedBy: "\r\n")
        #expect(semicolon[0].hasPrefix("Date;Type;Account;To Account;Amount"))
        #expect(semicolon[1].hasPrefix("2026-10-20 09:00:00;Expense;Everyday Savings;;-450.00;;INR;"))
        #expect(semicolon[1].hasSuffix(";\"Bread, buns; cake\";Two\tboxes"))

        let tab = text(.tab).components(separatedBy: "\r\n")
        #expect(tab[0].hasPrefix("Date\tType\tAccount\tTo Account\tAmount"))
        #expect(tab[1].hasSuffix("\tBread, buns; cake\t\"Two\tboxes\""))
        #expect(tab[2].hasSuffix("\tStreamBox\t"))
    }

    @Test("E1: a quote is doubled and a formula cell keeps its apostrophe with every delimiter")
    func quotesAndFormulas() {
        #expect(CSVWriter.field("Say \"hi\"", delimiter: ";") == "\"Say \"\"hi\"\"\"")
        #expect(CSVWriter.field("a,b", delimiter: ";") == "a,b")
        #expect(CSVWriter.field("a;b", delimiter: ";") == "\"a;b\"")
        #expect(CSVWriter.field("a;b", delimiter: "\t") == "a;b")
        #expect(CSVWriter.field("a\tb", delimiter: "\t") == "\"a\tb\"")
        #expect(TransactionCSVWriter.protectedText("\tTotal") == "'\tTotal")
    }

    @Test("E1: every delimiter writes UTF-8 with a byte order mark and reads back through the importer")
    func bomAndRoundTrip() throws {
        for delimiter in CSVDelimiter.allCases {
            let data = TransactionCSVWriter.data(
                for: transactions(),
                lookup: lookup,
                dateStyle: .iso8601,
                delimiter: delimiter,
            )
            #expect(Array(data.prefix(3)) == CSVWriter.byteOrderMark, "\(delimiter)")
            #expect(String(data: data.dropFirst(3), encoding: .utf8) == text(delimiter), "\(delimiter)")
            let pipeline = DefaultImportPipeline()
            let file = try pipeline.open(data)
            let settings = ImportReadSettings(
                mapping: file.suggestedMapping,
                dateOrder: .yearMonthDay,
                decimalSeparator: .period,
                timeZone: F.timeZone(),
            )
            let preview = pipeline.preview(
                rows: pipeline.rows(in: file, settings: settings),
                ledger: F.ledger(),
                choices: ImportChoices(),
                settings: settings,
                defaultCurrency: "INR",
            )
            #expect(preview.failedCount == 0, "\(delimiter)")
            let drafts = preview.rows.compactMap(\.draft)
            #expect(drafts.map(\.amount) == [F.dec("450"), F.dec("649")], "\(delimiter)")
            #expect(drafts.first?.details == "Bread, buns; cake", "\(delimiter)")
            #expect(drafts.first?.note == "Two\tboxes", "\(delimiter)")
        }
    }

    @Test("E1: a Tab file ends in .tsv; Comma and Semicolon files end in .csv")
    func fileNames() throws {
        let today = CalendarDay(year: 2026, month: 10, day: 25)
        let range = TransactionExportOptions.Range.days(
            from: CalendarDay(year: 2026, month: 10, day: 1),
            through: CalendarDay(year: 2026, month: 10, day: 31),
        )
        #expect(TransactionExportOptions().fileName(today: today) == "little-orbit_2026-10-25.csv")
        #expect(
            TransactionExportOptions(delimiter: .semicolon).fileName(today: today) == "little-orbit_2026-10-25.csv"
        )
        #expect(TransactionExportOptions(delimiter: .tab).fileName(today: today) == "little-orbit_2026-10-25.tsv")
        #expect(
            TransactionExportOptions(range: range, delimiter: .tab).fileName(today: today)
                == "little-orbit_2026-10-01_to_2026-10-31.tsv"
        )
        #expect(CSVDelimiter.tab.contentTypeIdentifier == "public.tab-separated-values-text")
        #expect(CSVDelimiter.semicolon.contentTypeIdentifier == "public.comma-separated-values-text")

        let repository = try FakeLedgerRepository(accounts: F.accounts(), categories: F.categories())
        try repository.savePayee(F.payees()[0])
        for transaction in transactions() {
            try repository.saveTransaction(transaction)
        }
        let useCase = DefaultExportTransactionsUseCase(repository: repository)
        let export = try useCase.export(TransactionExportOptions(delimiter: .tab), locale: F.india, today: today)
        #expect(export.fileName == "little-orbit_2026-10-25.tsv")
        #expect(export.delimiter == .tab)
        #expect(export.rowCount == 2)
        let written = try CSVText.decode(export.data)
        #expect(written.hasPrefix("Date\tType\t"))
    }
}

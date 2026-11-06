import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// The export sheet's Delimiter choice (#189 E1, D387.8), over the real export use case.
@Suite("CSV export Delimiter (#189 E1)")
@MainActor
struct CSVExportDelimiterTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    /// Made-up rows: Corner Bakery ₹450.00 and StreamBox ₹649.00, on 20 and 21 Oct 2026 in India.
    private func repository() throws -> InMemoryLedgerRepository {
        let repository = try F.repository()
        let savings = try F.account("Everyday Savings", in: repository)
        for (offset, amount, details) in [(0, Decimal(450), "Corner Bakery; buns"), (1, Decimal(649), "StreamBox")] {
            let date = Date(timeIntervalSince1970: 1_792_454_400 + Double(offset) * 86_400)
            try repository.saveTransaction(
                Transaction(
                    type: .expense,
                    amount: amount,
                    date: date,
                    timeZoneID: "Asia/Kolkata",
                    accountID: savings.id,
                    details: details,
                )
            )
        }
        return repository
    }

    private func model(_ exporting: any ExportTransactionsUseCase) -> CSVExportViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = F.zone
        // 25 Oct 2026, noon in India.
        let now = Date(timeIntervalSince1970: 1_792_908_000)
        return CSVExportViewModel(exporting: exporting, locale: F.india, calendar: calendar, now: { now })
    }

    private func model() throws -> CSVExportViewModel {
        let model = model(DefaultExportTransactionsUseCase(repository: try repository()))
        model.load()
        return model
    }

    // MARK: E1

    @Test("E1: the Delimiter menu offers Comma, Semicolon and Tab, with Comma chosen first")
    func delimiterChoices() throws {
        let model = try model()
        #expect(model.delimiter == .comma)
        #expect(model.options.delimiter == .comma)
        #expect(ImportExportText.delimiter == "Delimiter")
        #expect(CSVDelimiter.allCases.map(ImportExportText.delimiterName) == ["Comma", "Semicolon", "Tab"])
    }

    @Test("E1: the footer no longer says comma-separated and still says UTF-8 with BOM")
    func footer() {
        #expect(!ImportExportText.formatFooter.localizedCaseInsensitiveContains("comma"))
        #expect(ImportExportText.formatFooter.hasPrefix("UTF-8 with BOM. Columns: Date, Type, Account"))
    }

    @Test("E1: a Tab export is a UTF-8 .tsv file with a BOM, and the save panel offers the TSV type")
    func tabExport() throws {
        let model = try model()
        let count = model.count
        model.delimiter = .tab
        #expect(model.count == count)
        #expect(model.exportContentTypeIdentifier == "public.tab-separated-values-text")
        model.export()
        let file = try #require(model.pendingFile)
        #expect(file.fileName == "little-orbit_2026-10-25.tsv")
        #expect(model.defaultFileName == "little-orbit_2026-10-25")
        #expect(model.exportContentTypeIdentifier == "public.tab-separated-values-text")
        #expect(Array(file.data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let lines = try CSVText.decode(file.data).components(separatedBy: "\r\n")
        #expect(lines[0].hasPrefix("Date\tType\tAccount\tTo Account\tAmount"))
        #expect(lines[1].hasSuffix("\tCorner Bakery; buns\t"))
    }

    @Test("E1: a Semicolon export is a UTF-8 .csv file with a BOM that quotes a cell with a semicolon")
    func semicolonExport() throws {
        let model = try model()
        model.delimiter = .semicolon
        model.export()
        let file = try #require(model.pendingFile)
        #expect(file.fileName == "little-orbit_2026-10-25.csv")
        #expect(model.defaultFileName == "little-orbit_2026-10-25")
        #expect(model.exportContentTypeIdentifier == "public.comma-separated-values-text")
        #expect(Array(file.data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let lines = try CSVText.decode(file.data).components(separatedBy: "\r\n")
        #expect(lines[0].hasPrefix("Date;Type;Account;To Account;Amount"))
        #expect(lines[1].hasSuffix(";\"Corner Bakery; buns\";"))
    }
}

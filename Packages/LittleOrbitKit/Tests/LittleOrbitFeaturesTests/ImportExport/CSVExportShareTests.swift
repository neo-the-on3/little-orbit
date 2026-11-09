import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Share… on the export sheet (#189 E3): the same file and name Export writes, over the real export use case.
@Suite("CSV export Share (#189 E3)")
@MainActor
struct CSVExportShareTests {
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

    @Test("E3: Share… gets the same bytes and name Export writes, for every delimiter and range")
    func shareMatchesExport() throws {
        let model = try model()
        for (delimiter, range) in [(CSVDelimiter.comma, CSVExportViewModel.Range.allTime), (.tab, .thisMonth)] {
            model.delimiter = delimiter
            model.range = range
            let shared = try model.shareFile()
            #expect(!model.isExporterPresented)
            #expect(model.pendingFile == nil)
            #expect(shared.fileName == model.shareFileName)
            model.export()
            let exported = try #require(model.pendingFile)
            #expect(shared == exported)
            model.exportFinished(saved: false, failed: false)
        }
        #expect(model.shareFileName == "little-orbit_2026-10-01_to_2026-10-31.tsv")
    }

    @Test("E3: the shared file on disk has Export's name and bytes, and an earlier shared file is removed")
    func shareFileOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CSVShareTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try model()
        model.delimiter = .tab
        let first = try CSVShareFile.write(try model.shareFile(), under: root)
        #expect(first.lastPathComponent == "little-orbit_2026-10-25.tsv")
        model.export()
        #expect(try Data(contentsOf: first) == model.pendingFile?.data)
        model.delimiter = .comma
        let second = try CSVShareFile.write(try model.shareFile(), under: root)
        #expect(second.lastPathComponent == "little-orbit_2026-10-25.csv")
        #expect(!FileManager.default.fileExists(atPath: first.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: second.path(percentEncoded: false)))
    }

    @Test("E3: a share that can't make the file shows the export failure alert")
    func shareFailure() throws {
        let model = model(FailingExport())
        model.load()
        #expect(throws: ExportFailure.self) { try model.shareFile() }
        #expect(model.alert?.title == ImportExportText.exportFailedTitle)
        #expect(ImportExportText.share == "Share…")
    }
}

private struct ExportFailure: Error {}

/// An export use case whose export always fails.
@MainActor
private struct FailingExport: ExportTransactionsUseCase {
    func accounts() throws -> [Account] { [] }
    func count(_ options: TransactionExportOptions) throws -> Int { 1 }
    func export(_ options: TransactionExportOptions, locale: Locale, today: CalendarDay) throws -> TransactionExport {
        throw ExportFailure()
    }
}

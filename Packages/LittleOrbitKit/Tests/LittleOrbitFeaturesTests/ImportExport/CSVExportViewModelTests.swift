import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The export sheet's model over the real export use case (#30).
@Suite("CSV export screen (#30)")
@MainActor
struct CSVExportViewModelTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    private func repository() throws -> InMemoryLedgerRepository {
        let repository = try F.repository()
        let savings = try F.account("Everyday Savings", in: repository)
        let wallet = try F.account("Corner Wallet", in: repository)
        let calendar = Calendar(identifier: .gregorian)
        for (day, account) in [(1, savings), (15, wallet), (40, savings)] {
            let date = calendar.date(byAdding: .day, value: day - 1, to: Date(timeIntervalSince1970: 1_790_812_800))!
            try repository.saveTransaction(
                Transaction(type: .expense, amount: 100, date: date, timeZoneID: "Asia/Kolkata", accountID: account.id)
            )
        }
        return repository
    }

    private func model(_ repository: InMemoryLedgerRepository) -> CSVExportViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = F.zone
        // 25 Oct 2026, noon in India.
        let now = Date(timeIntervalSince1970: 1_792_908_000)
        return CSVExportViewModel(
            exporting: DefaultExportTransactionsUseCase(repository: repository),
            locale: F.india,
            calendar: calendar,
            now: { now },
        )
    }

    @Test("The count follows the accounts and the date range")
    func count() throws {
        let model = model(try repository())
        model.load()
        #expect(model.accounts.count == 3)
        #expect(model.count == 3)
        #expect(model.countText == "Will export 3 transactions")
        model.scope = .accounts
        #expect(model.count == 0)
        #expect(model.countText == "No transactions match.")
        #expect(!model.canExport)
        model.toggleAccount(model.accounts[1].id)
        #expect(model.count == 1)
        model.scope = .all
        model.range = .thisMonth
        #expect(model.count == 2)
    }

    @Test("Export makes the file and opens the save panel; closing it clears the file")
    func export() throws {
        let model = model(try repository())
        model.load()
        model.export()
        #expect(model.isExporterPresented)
        #expect(model.defaultFileName == "little-orbit_2026-10-25")
        let data = try #require(model.pendingFile?.data)
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let text = try CSVText.decode(data)
        #expect(text.hasPrefix("Date,Type,Account,To Account,Amount"))
        model.exportFinished(saved: true, failed: false)
        #expect(model.pendingFile == nil)
        #expect(model.alert == nil)
    }
}

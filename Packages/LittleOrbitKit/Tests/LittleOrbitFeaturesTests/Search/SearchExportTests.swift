import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// #187: Export CSV of the results on screen. Today is Tue 20 Oct 2026 in India. All names and amounts are made up.
@MainActor
@Suite("Search export")
struct SearchTableExportTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    static let dining = TransactionCategory(name: "Coffee Runs")
    static let copperCup = Payee(name: "Copper Cup Cafe")
    static let bakery = Payee(name: "Bakery Lane")

    private func repository() throws -> InMemoryLedgerRepository {
        let repository = try F.repository()
        try repository.saveCategory(Self.dining)
        try repository.savePayee(Self.copperCup)
        try repository.savePayee(Self.bakery)
        for (amount, day, payee) in [
            (Decimal(350), 25, Self.copperCup), (320, 20, Self.copperCup), (90, 19, Self.bakery),
            (410, 17, Self.copperCup), (999, 15, Self.bakery),
        ] {
            try repository.saveTransaction(
                F.expense(amount, on: F.date(2026, 10, day), category: Self.dining.id, payee: payee.id)
            )
        }
        return repository
    }

    private func model(
        _ repository: InMemoryLedgerRepository,
        query: String,
        exporting: (any ExportSearchResultsUseCase)? = DefaultExportSearchResultsUseCase(),
    ) -> TransactionSearchViewModel {
        let model = TransactionSearchViewModel(
            search: DefaultSearchTransactionsUseCase(repository: repository),
            exporting: exporting,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            defaultCurrency: "INR",
        )
        model.query = query
        model.load()
        return model
    }

    // MARK: Export CSV

    @Test("#28 AC 4: Export CSV writes only the matches on screen, Upcoming included, then the exporter opens")
    func exportsMatches() throws {
        let model = model(try repository(), query: "copper")
        #expect(model.canExport)
        #expect(model.exportTitle == "Export CSV…")
        #expect(model.exportRowTitle == "Export CSV")
        model.export()
        let file = try #require(model.exportFile)
        #expect(model.isExporterPresented)
        #expect(file.rowCount == 3)
        #expect(model.exportFileName == "little-orbit_search_2026-10-20")
        let text = try #require(String(bytes: file.data, encoding: .utf8))
        #expect(text.contains("Copper Cup Cafe"))
        #expect(!text.contains("Bakery Lane"))
        model.exportFinished(failed: false)
        #expect(model.exportFile == nil)
        #expect(!model.isExporterPresented)
        #expect(model.exportFailure == nil)
    }

    @Test("A failed save shows Couldn’t Export; no results or no export wired in offers no Export CSV (D321)")
    func exportStates() throws {
        let repository = try repository()
        let model = model(repository, query: "copper")
        model.export()
        model.exportFinished(failed: true)
        #expect(
            model.exportFailure
                == SearchFailure(title: "Couldn’t Export", message: "The CSV file couldn’t be created. Try again.")
        )
        #expect(model.exportFile == nil)

        let none = self.model(repository, query: "lantern tea house")
        #expect(none.isNoResults)
        #expect(!none.canExport)
        none.export()
        #expect(none.exportFile == nil)

        let unwired = self.model(repository, query: "copper", exporting: nil)
        #expect(!unwired.canExport)
    }

    @Test("D323.1: search export goes through the hardened writer, so a formula-like cell gets one apostrophe")
    func formulaCellsAreText() throws {
        let repository = try repository()
        let formula = Payee(name: "=HYPERLINK(1)")
        try repository.savePayee(formula)
        try repository.saveTransaction(
            F.expense(75, on: F.date(2026, 10, 18), payee: formula.id, details: "+Copper refill")
        )
        let model = model(repository, query: "copper")
        model.export()
        let file = try #require(model.exportFile)
        let text = try #require(String(bytes: file.data, encoding: .utf8))
        #expect(text.contains("'=HYPERLINK(1)"))
        #expect(text.contains("'+Copper refill"))
        // Amounts stay numbers: an expense's minus sign is never prefixed.
        #expect(text.contains(",-75.00,"))
        #expect(!text.contains("'-75.00"))
    }
}

import Foundation
import LittleOrbitDomain
import Testing

/// Export CSV of search results (#187, #28 AC 4): only the matches, through the #30 writer. All names and amounts
/// are made up.
@MainActor
@Suite("Search export")
struct ExportSearchResultsUseCaseTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    static let today = F.day(2026, 10, 21)
    static let cafe = Payee(name: "Copper Cup Cafe")

    /// The fixture's zone under its current name: Linux's time zone data has no `Asia/Calcutta` alias for the
    /// writer's date formatter. The offset, and so every day, is the same.
    private func snapshot(_ transactions: [Transaction]) -> TransactionSearchSnapshot {
        let kolkata = transactions.map { transaction in
            var copy = transaction
            copy.timeZoneID = "Asia/Kolkata"
            return copy
        }
        return TransactionSearchSnapshot(
            ledger: TransactionLedger(accounts: F.accounts, transactions: kolkata, payees: [Self.cafe]),
            tags: [],
        )
    }

    private func lines(_ export: TransactionExport) -> [String] {
        let text = String(bytes: export.data, encoding: .utf8) ?? ""
        return text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    }

    @Test("Only the matching transactions are written, oldest first, after the writer's header")
    func matchesOnly() {
        var early = F.expense(320, on: F.date(2026, 10, 9))
        early.payeeID = Self.cafe.id
        var late = F.expense(410, on: F.date(2026, 10, 17))
        late.payeeID = Self.cafe.id
        let other = F.expense(999, on: F.date(2026, 10, 12))
        let snapshot = snapshot([late, other, early])
        let result = snapshot.search(
            .parse("copper"),
            filter: TransactionSearchFilter(),
            today: Self.today,
            defaultCurrency: "INR",
        )

        let export = DefaultExportSearchResultsUseCase().export(result, from: snapshot, today: Self.today)

        #expect(export.rowCount == 2)
        let lines = lines(export)
        #expect(lines.count == 3)
        #expect(lines[0].hasSuffix(TransactionCSVWriter.header.joined(separator: ",")))
        #expect(lines[1].hasPrefix("2026-10-09"))
        #expect(lines[1].contains("-320.00"))
        #expect(lines[2].hasPrefix("2026-10-17"))
        #expect(!lines.joined().contains("999"))
        #expect(export.fileName == "little-orbit_search_2026-10-21.csv")
    }

    @Test("Upcoming matches are written too, and a transfer is one row even when listed from both sides (D25, D47)")
    func upcomingAndTransfers() {
        let upcoming = F.expense(50, on: F.date(2026, 10, 25))
        let transfer = F.transfer(1_000, on: F.date(2026, 10, 10), to: F.walletID)
        let snapshot = snapshot([upcoming, transfer])
        var result = snapshot.search(
            .parse(""),
            filter: TransactionSearchFilter(),
            today: Self.today,
            defaultCurrency: "INR",
        )
        #expect(result.upcomingCount == 1)
        // A result that lists the same transfer twice still writes it once.
        result.days.append(contentsOf: result.days)

        let export = DefaultExportSearchResultsUseCase().export(result, from: snapshot, today: Self.today)

        #expect(export.rowCount == 2)
        let lines = lines(export)
        #expect(lines.count == 3)
        #expect(lines[1].contains(",Transfer,"))
        #expect(lines[2].hasPrefix("2026-10-25"))
    }

    @Test("D323 addendum: the file name is the local day, zero-padded, at either end of the year")
    func fileNames() {
        let export = DefaultExportSearchResultsUseCase()
        for (day, name) in [
            (F.day(2026, 1, 5), "little-orbit_search_2026-01-05.csv"),
            (F.day(2026, 12, 31), "little-orbit_search_2026-12-31.csv"),
        ] {
            #expect(export.export(TransactionSearchResult(), from: snapshot([]), today: day).fileName == name)
        }
    }

    @Test("An empty result writes the header only")
    func emptyResult() {
        let export = DefaultExportSearchResultsUseCase()
            .export(
                TransactionSearchResult(),
                from: snapshot([]),
                today: Self.today,
            )
        #expect(export.rowCount == 0)
        #expect(lines(export).count == 1)
    }
}

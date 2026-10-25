import Foundation

/// Export CSV of search results (#187, #28 AC “only the matching transactions are written to CSV”).
///
/// The file is the app's own CSV, written by `TransactionCSVWriter`, the same writer as Export Transactions to CSV
/// (#30), so the two files read back the same way and share any change to the writer. View models depend on this
/// protocol; the export runs over the snapshot the screen already searched, so it doesn't read the store again.
/// It goes straight to the save panel with the CSV defaults, ISO 8601 dates and no options sheet (D323 addendum).
@MainActor
public protocol ExportSearchResultsUseCase {
    /// The file for every transaction in `result`, Upcoming matches included (D47 lists them), each once.
    func export(
        _ result: TransactionSearchResult,
        from snapshot: TransactionSearchSnapshot,
        today: CalendarDay,
    ) -> TransactionExport
}

public struct DefaultExportSearchResultsUseCase: ExportSearchResultsUseCase {
    public init() {}

    public func export(
        _ result: TransactionSearchResult,
        from snapshot: TransactionSearchSnapshot,
        today: CalendarDay,
    ) -> TransactionExport {
        let transactions = Self.transactions(in: result)
        return TransactionExport(
            data: TransactionCSVWriter.data(
                for: transactions,
                lookup: TransactionCSVLookup(snapshot.ledger),
                dateStyle: .iso8601,
            ),
            rowCount: transactions.count,
            fileName: Self.fileName(today: today),
        )
    }

    /// The matched transactions, each once, oldest first, as Export Transactions to CSV orders its rows.
    static func transactions(in result: TransactionSearchResult) -> [Transaction] {
        var seen = Set<UUID>()
        return result.days
            .flatMap(\.matches)
            .map(\.transaction)
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.date, $0.createdAt.timeIntervalSince1970) < ($1.date, $1.createdAt.timeIntervalSince1970) }
    }

    /// `little-orbit_search_2026-10-25.csv` for the user's local day (D323 addendum): a file value, not screen
    /// text. The day is written by an ISO 8601 date formatter, never pieced together by hand.
    static func fileName(today: CalendarDay) -> String {
        let noon = TransactionCalendar.noon(on: today, timeZoneID: "UTC") ?? Date(timeIntervalSince1970: 0)
        let day = noon.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
        return "little-orbit_search_" + day + ".csv"
    }
}

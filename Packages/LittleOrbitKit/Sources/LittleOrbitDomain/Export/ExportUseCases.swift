import Foundation

/// Which transactions Export Transactions to CSV writes.
public struct TransactionExportOptions: Equatable, Sendable {
    public enum Range: Equatable, Sendable {
        case allTime
        /// From the first day to the last, both included, by each transaction's own calendar day.
        case days(from: CalendarDay, through: CalendarDay)
    }

    /// `nil` exports every account; otherwise only transactions in or out of these.
    public var accountIDs: Set<UUID>?
    public var range: Range
    public var iso8601Dates: Bool
    /// Comma by default; Tab files end in `.tsv` (#189 E1, D387.8).
    public var delimiter: CSVDelimiter

    public init(
        accountIDs: Set<UUID>? = nil,
        range: Range = .allTime,
        iso8601Dates: Bool = true,
        delimiter: CSVDelimiter = .comma,
    ) {
        self.accountIDs = accountIDs
        self.range = range
        self.iso8601Dates = iso8601Dates
        self.delimiter = delimiter
    }

    /// `little-orbit_2026-10-25.csv`; with a range, its days; `.tsv` for Tab (design rule, D387.8). Export and
    /// Share both use it, so the two write the same name (#189 E3).
    public func fileName(today: CalendarDay) -> String {
        let stem =
            switch range {
            case .allTime:
                "little-orbit_\(Self.text(today))"
            case .days(let first, let last):
                "little-orbit_\(Self.text(first))_to_\(Self.text(last))"
            }
        return stem + "." + delimiter.fileExtension
    }

    private static func text(_ day: CalendarDay) -> String {
        String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }
}

/// An export's file, ready for the system exporter or the share sheet.
public struct TransactionExport: Equatable, Sendable {
    public var data: Data
    public var rowCount: Int
    /// `little-orbit_2026-10-25.csv`; with a range, its days; `.tsv` for Tab (design rule, D387.8).
    public var fileName: String
    /// The delimiter it was written with, which picks the file type.
    public var delimiter: CSVDelimiter = .comma
}

/// Export Transactions to CSV (#30). Offline, on this device only (D14).
@MainActor
public protocol ExportTransactionsUseCase {
    /// The live accounts, hidden ones included, in the user's order, for choosing which to export.
    func accounts() throws -> [Account]
    /// How many transactions `options` would write, for “Will export”.
    func count(_ options: TransactionExportOptions) throws -> Int
    func export(_ options: TransactionExportOptions, locale: Locale, today: CalendarDay) throws -> TransactionExport
}

@MainActor
public struct DefaultExportTransactionsUseCase: ExportTransactionsUseCase {
    private let repository: any LedgerRepository

    public init(repository: any LedgerRepository) {
        self.repository = repository
    }

    public func accounts() throws -> [Account] {
        try repository.accounts().filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    public func count(_ options: TransactionExportOptions) throws -> Int {
        selected(options, from: try repository.transactions()).count
    }

    public func export(_ options: TransactionExportOptions, locale: Locale, today: CalendarDay) throws
        -> TransactionExport
    {
        let ledger = TransactionLedger(
            accounts: try repository.accounts(),
            transactions: try repository.transactions(),
            categories: try repository.categories(),
            payees: try repository.payees(),
        )
        let transactions = selected(options, from: ledger.transactions)
        let data = TransactionCSVWriter.data(
            for: transactions,
            lookup: TransactionCSVLookup(ledger),
            dateStyle: options.iso8601Dates ? .iso8601 : .shortDate(locale),
            delimiter: options.delimiter,
        )
        return TransactionExport(
            data: data,
            rowCount: transactions.count,
            fileName: options.fileName(today: today),
            delimiter: options.delimiter,
        )
    }

    /// The live transactions the options pick, oldest first.
    func selected(_ options: TransactionExportOptions, from transactions: [Transaction]) -> [Transaction] {
        transactions
            .filter { transaction in
                guard transaction.deletedAt == nil else { return false }
                if let accounts = options.accountIDs {
                    let touches = [transaction.accountID, transaction.transferAccountID]
                        .contains { id in
                            id.map(accounts.contains) ?? false
                        }
                    guard touches else { return false }
                }
                if case .days(let first, let last) = options.range {
                    let day = TransactionCalendar.ownDay(of: transaction.date, timeZoneID: transaction.timeZoneID)
                    return day >= first && day <= last
                }
                return true
            }
            .sorted { ($0.date, $0.createdAt.timeIntervalSince1970) < ($1.date, $1.createdAt.timeIntervalSince1970) }
    }
}

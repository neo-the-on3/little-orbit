import Foundation

/// Loads “What do I spend my money on?” and its drill-down (#27 core). The spending report's view model depends
/// only on this protocol; the App target wires in `DefaultLoadSpendingReportUseCase`.
@MainActor
public protocol LoadSpendingReportUseCase {
    /// The report for `period` in `currencyCode`, or, when that currency has no spending in the period, in the
    /// first of the period's currencies (the default currency first).
    func spendingReport(for period: ReportPeriod, currencyCode: String?) throws -> SpendingReport
    /// The transactions behind one row (`categoryID` `nil` is Uncategorised), newest first.
    func spendingEntries(
        for period: ReportPeriod,
        currencyCode: String,
        categoryID: UUID?,
    ) throws -> [SpendingReportEntry]
}

@MainActor
public struct DefaultLoadSpendingReportUseCase: LoadSpendingReportUseCase {
    private let source: any LedgerBackupSource
    private let defaultCurrency: String
    private let timeZone: TimeZone
    private let now: @MainActor () -> Date

    /// `source` is read once per call, as one whole-ledger snapshot without attachment bytes (Tech Architect's
    /// NB2 on #185), rather than once per record type. `timeZone` and `now` only decide which day is today, and
    /// so which month or year is “this” one. Each transaction still counts on its own day in its own zone.
    public init(
        source: any LedgerBackupSource,
        defaultCurrency: String = CurrencyCode.deviceDefault,
        timeZone: TimeZone = .current,
        now: @escaping @MainActor () -> Date = { Date() },
    ) {
        self.source = source
        self.defaultCurrency = defaultCurrency
        self.timeZone = timeZone
        self.now = now
    }

    public func spendingReport(for period: ReportPeriod, currencyCode: String?) throws -> SpendingReport {
        SpendingReportBuilder.report(
            in: try source.backupSnapshot(),
            period: period,
            today: TransactionTiming.today(now(), timeZone: timeZone),
            currencyCode: currencyCode,
            defaultCurrency: defaultCurrency,
        )
    }

    public func spendingEntries(
        for period: ReportPeriod,
        currencyCode: String,
        categoryID: UUID?,
    ) throws -> [SpendingReportEntry] {
        SpendingReportBuilder.entries(
            in: try source.backupSnapshot(),
            period: period,
            today: TransactionTiming.today(now(), timeZone: timeZone),
            currencyCode: currencyCode,
            categoryID: categoryID,
        )
    }
}

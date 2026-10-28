import Foundation

/// Loads “What do I spend my money on?”, by payee “Where do I spend the most?”, by income “Where does my money
/// come from?”, and their drill-downs, and income vs expenses by month (#27, #184). The spending report's view model depends
/// only on this protocol; the App target wires in `DefaultLoadSpendingReportUseCase`. Both calls are async, so
/// the report is built off the main actor (Tech Architect's NB1 on #185).
public protocol LoadSpendingReportUseCase: Sendable {
    /// The report for `query`, in its currency or, when that currency has no spending in the range, in the
    /// first of the range's currencies (the default currency first).
    func spendingReport(_ query: SpendingReportQuery) async throws -> SpendingReport
    /// The transactions behind one row of `query`'s report, newest first. `categoryID` is the row's ID: a
    /// category's, or a payee's when the query groups by payee; `nil` is Uncategorised or No Payee.
    func spendingEntries(_ query: SpendingReportQuery, categoryID: UUID?) async throws -> [SpendingReportEntry]
    /// Income vs expenses by month for `query`'s range, currency and accounts (#184 slice 5), also the Reports
    /// list's This Month summary.
    func incomeExpenseReport(_ query: SpendingReportQuery) async throws -> IncomeExpenseReport
}

@MainActor
public struct DefaultLoadSpendingReportUseCase: LoadSpendingReportUseCase {
    private let source: any LedgerBackupSource
    private let defaultCurrency: String

    /// `source` is read once per call, as one whole-ledger snapshot without attachment bytes (Tech Architect's
    /// NB2 on #185). The store lives on the main actor, so that read stays there: it's the store's own copy of
    /// the ledger in memory. Counting, sorting and the shares run off the main actor.
    public init(source: any LedgerBackupSource, defaultCurrency: String = CurrencyCode.deviceDefault) {
        self.source = source
        self.defaultCurrency = defaultCurrency
    }

    public func spendingReport(_ query: SpendingReportQuery) async throws -> SpendingReport {
        let snapshot = try source.backupSnapshot()
        let defaultCurrency = defaultCurrency
        return try await ReportWork.offMain {
            SpendingReportBuilder.report(in: snapshot, query: query, defaultCurrency: defaultCurrency)
        }
    }

    public func spendingEntries(_ query: SpendingReportQuery, categoryID: UUID?) async throws -> [SpendingReportEntry] {
        let snapshot = try source.backupSnapshot()
        let defaultCurrency = defaultCurrency
        return try await ReportWork.offMain {
            SpendingReportBuilder.entries(
                in: snapshot,
                query: query,
                categoryID: categoryID,
                defaultCurrency: defaultCurrency,
            )
        }
    }
}

extension DefaultLoadSpendingReportUseCase {
    public func incomeExpenseReport(_ query: SpendingReportQuery) async throws -> IncomeExpenseReport {
        let snapshot = try source.backupSnapshot()
        let defaultCurrency = defaultCurrency
        return try await ReportWork.offMain {
            IncomeExpenseReportBuilder.report(in: snapshot, query: query, defaultCurrency: defaultCurrency)
        }
    }
}

/// Report work off the main actor.
public enum ReportWork {
    /// Runs `work` on a detached task and returns its result. Cancelling the caller cancels it, and a cancelled
    /// call throws `CancellationError` rather than returning a stale report.
    public static func offMain<Result: Sendable>(
        _ work: @escaping @Sendable () -> Result
    ) async throws -> Result {
        let task = Task.detached(priority: .userInitiated) { () throws -> Result in
            try Task.checkCancellation()
            return work()
        }
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        return result
    }
}

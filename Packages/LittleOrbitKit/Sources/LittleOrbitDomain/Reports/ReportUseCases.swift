import Foundation

/// Loads “What do I spend my money on?” and its drill-down (#27, #184). The spending report's view model depends
/// only on this protocol; the App target wires in `DefaultLoadSpendingReportUseCase`. Both calls are async, so
/// the report is built off the main actor (Tech Architect's NB1 on #185).
public protocol LoadSpendingReportUseCase: Sendable {
    /// The report for `query`, in its currency or, when that currency has no spending in the range, in the
    /// first of the range's currencies (the default currency first).
    func spendingReport(_ query: SpendingReportQuery) async throws -> SpendingReport
    /// The transactions behind one row of `query`'s report (`categoryID` `nil` is Uncategorised), newest first.
    func spendingEntries(_ query: SpendingReportQuery, categoryID: UUID?) async throws -> [SpendingReportEntry]
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
        return try await ReportWork.offMain {
            SpendingReportBuilder.entries(in: snapshot, query: query, categoryID: categoryID)
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

import Foundation
import Observation

/// An open drill-down (#27): one row's transactions, kept current while it's on screen. It reads them again
/// after every change to the shared store, from any window, without waiting for the report's list, which
/// isn't on screen while the drill-down is pushed over it (Tester's iPad two-window check on #185).
@MainActor
@Observable
public final class SpendingDrillDownModel {
    /// `nil` before the first read, and when the transactions can't be read.
    public private(set) var drillDown: SpendingDrillDown?
    /// The last read failed: the drill-down shows the load failure.
    public private(set) var loadFailed = false
    /// The row it was opened from; its title and share follow the report's current row.
    public let row: SpendingRowModel

    @ObservationIgnored private let report: SpendingReportViewModel

    init(report: SpendingReportViewModel, row: SpendingRowModel) {
        self.report = report
        self.row = row
    }

    /// Reads the row's transactions from the report's current period, currency and accounts.
    public func load() async {
        drillDown = await report.drillDown(for: row)
        loadFailed = drillDown == nil
    }

    /// After a change to the shared store at `storeRevision`: the report reads the store again (once per change,
    /// whichever screen asks first), so the row's share and the period are current, then the transactions.
    public func refresh(at storeRevision: Int) async {
        await report.load(at: storeRevision)
        await load()
    }

    /// Try Again after a failed read (D318.5): the report reads the store again, then the transactions.
    public func retry() async {
        await report.load()
        await load()
    }
}

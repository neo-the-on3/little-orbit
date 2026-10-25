import Foundation
import LittleOrbitDomain

/// Everything Reports needs (#27 core), built once by the composition root (the App target) from the injected
/// use case. It makes the spending report's view model for each screen that shows it.
@MainActor
public final class ReportsFeature {
    /// The shared store's change signal, so an open report reloads after any edit, from any window.
    public let updates: LedgerUpdates
    private let spendingReport: any LoadSpendingReportUseCase
    private let locale: Locale
    private let timeZone: TimeZone
    private let now: () -> Date

    public init(
        spendingReport: any LoadSpendingReportUseCase,
        updates: LedgerUpdates,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.spendingReport = spendingReport
        self.updates = updates
        self.locale = locale
        self.timeZone = timeZone
        self.now = now
    }

    public var title: String { ReportText.reportsTitle }
    public var spendingQuestion: String { ReportText.spendingQuestion }

    public func makeSpendingReport() -> SpendingReportViewModel {
        SpendingReportViewModel(useCase: spendingReport, locale: locale, timeZone: timeZone, now: now)
    }
}

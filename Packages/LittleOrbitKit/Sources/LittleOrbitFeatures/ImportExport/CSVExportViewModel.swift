import Foundation
import LittleOrbitDomain
import Observation

/// Export Transactions to CSV (#30): every account or chosen ones, all time, this month or a custom range, ISO or
/// short dates, and a Comma, Semicolon or Tab delimiter (#189 E1). The file goes to the system save panel or Files,
/// or to the share sheet the user opens with Share… (#189 E3); it never leaves the device otherwise (D14).
@MainActor
@Observable
public final class CSVExportViewModel {
    public enum Scope: Hashable, Sendable {
        case all
        case accounts
    }

    public enum Range: Hashable, Sendable {
        case allTime
        case thisMonth
        case custom
    }

    public var scope: Scope = .all {
        didSet { refreshCount() }
    }
    public var selectedAccountIDs: Set<UUID> = [] {
        didSet { refreshCount() }
    }
    public var range: Range = .allTime {
        didSet { refreshCount() }
    }
    public var customStart: Date {
        didSet { refreshCount() }
    }
    public var customEnd: Date {
        didSet { refreshCount() }
    }
    public var iso8601Dates = true
    /// Comma by default; Tab writes a `.tsv` file (#189 E1, D387.8). The count doesn't depend on it.
    public var delimiter: CSVDelimiter = .comma
    public private(set) var accounts: [Account] = []
    public private(set) var count = 0
    /// The file waiting for the save panel.
    public private(set) var pendingFile: TransactionExport?
    public var isExporterPresented = false
    public var alert: ImportAlert?

    @ObservationIgnored private let exporting: any ExportTransactionsUseCase
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    /// An export sheet always counts as unsaved, like Export Backup, so a tapped reminder leaves it open (S33).
    public var hasUnsavedEdits: Bool { true }

    public init(
        exporting: any ExportTransactionsUseCase,
        locale: Locale = .current,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
    ) {
        self.exporting = exporting
        self.locale = locale
        self.calendar = calendar
        self.now = now
        let today = now()
        customStart = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        customEnd = today
    }

    public func load() {
        do {
            accounts = try exporting.accounts()
        } catch {
            accounts = []
        }
        refreshCount()
    }

    public var options: TransactionExportOptions {
        TransactionExportOptions(
            accountIDs: scope == .accounts ? selectedAccountIDs : nil,
            range: exportRange,
            iso8601Dates: iso8601Dates,
            delimiter: delimiter,
        )
    }

    public var countText: String {
        count == 0 ? ImportExportText.nothingToExport : ImportExportText.willExport(count)
    }

    public var canExport: Bool {
        count > 0
    }

    public func toggleAccount(_ id: UUID) {
        if selectedAccountIDs.contains(id) {
            selectedAccountIDs.remove(id)
        } else {
            selectedAccountIDs.insert(id)
        }
    }

    /// Makes the file and opens the save panel.
    public func export() {
        guard canExport else { return }
        do {
            pendingFile = try exporting.export(options, locale: locale, today: day(of: now()))
            isExporterPresented = true
        } catch {
            ImportLog.event(.exportFailed)
            alert = ImportAlert(
                title: ImportExportText.exportFailedTitle,
                message: ImportExportText.exportFailedMessage,
            )
        }
    }

    /// The save panel closed: saved, cancelled or failed.
    public func exportFinished(saved: Bool, failed: Bool) {
        if saved {
            ImportLog.exported(pendingFile?.rowCount ?? 0)
        }
        if failed {
            ImportLog.event(.exportFailed)
            alert = ImportAlert(
                title: ImportExportText.exportFailedTitle,
                message: ImportExportText.exportFailedMessage,
            )
        }
        pendingFile = nil
        isExporterPresented = false
    }

    /// The file name without `.csv` or `.tsv`, for the save panel, which adds the extension.
    public var defaultFileName: String? {
        pendingFile.map { file in
            String(file.fileName.dropLast(file.delimiter.fileExtension.count + 1))
        }
    }

    /// The save panel's file type: the pending file's, or the chosen delimiter's before there is one.
    public var exportContentTypeIdentifier: String {
        (pendingFile?.delimiter ?? delimiter).contentTypeIdentifier
    }

    // MARK: Share (#189 E3)

    /// The name Share… shows and the shared file has: the same as Export would write now.
    public var shareFileName: String {
        options.fileName(today: day(of: now()))
    }

    /// The file Share… hands to the share sheet: the same bytes and name Export would write with these options,
    /// made when the share sheet asks for it. The save panel isn't opened and nothing is left pending.
    public func shareFile() throws -> TransactionExport {
        do {
            return try exporting.export(options, locale: locale, today: day(of: now()))
        } catch {
            ImportLog.event(.exportFailed)
            alert = ImportAlert(
                title: ImportExportText.exportFailedTitle,
                message: ImportExportText.exportFailedMessage,
            )
            throw error
        }
    }

    private var exportRange: TransactionExportOptions.Range {
        switch range {
        case .allTime:
            return .allTime
        case .thisMonth:
            let today = day(of: now())
            let last = calendar.range(of: .day, in: .month, for: now())?.count ?? 31
            return .days(
                from: CalendarDay(year: today.year, month: today.month, day: 1),
                through: CalendarDay(year: today.year, month: today.month, day: last),
            )
        case .custom:
            let first = day(of: min(customStart, customEnd))
            let last = day(of: max(customStart, customEnd))
            return .days(from: first, through: last)
        }
    }

    private func day(of date: Date) -> CalendarDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    private func refreshCount() {
        count = (try? exporting.count(options)) ?? 0
    }
}

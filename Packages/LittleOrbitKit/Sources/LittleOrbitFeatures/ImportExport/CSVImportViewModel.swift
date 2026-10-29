import Foundation
import LittleOrbitDomain
import Observation

/// CSV import (#30): pick a file, check its columns, choose a target account when the file names none, match
/// names, review, import, and Undo Import. Depends only on the import use cases; the file reading, matching and
/// duplicate checks run off the main actor, so a 5,000-row file doesn't block the screen.
@MainActor
@Observable
public final class CSVImportViewModel {
    public enum Step: Equatable, Sendable {
        case pickFile
        case columns
        case account
        case match
        case review
        case summary
    }

    public internal(set) var step: Step = .pickFile {
        // D327.1: the notice stays until the user moves to another step or imports.
        didSet { if step != oldValue { dataChangedNotice = nil } }
    }
    public internal(set) var isWorking = false
    /// What the progress overlay says: reading the file, or saving the import.
    public internal(set) var workingText = ImportExportText.reading
    public var alert: ImportAlert?
    public var isConfirmingUndo = false
    public private(set) var fileName = ""
    public private(set) var file: ImportFile?
    public private(set) var mapping = ImportColumnMapping()
    public private(set) var detection: ImportDetection?
    public var dateOrder: ImportDateOrder = .dayMonthYear {
        didSet {
            if !isApplyingDetection { pickedDateOrder = dateOrder }
            if dateOrder != oldValue { settingChanged(owner: .columns) }
        }
    }
    public var decimalSeparator: ImportDecimalSeparator = .period {
        didSet {
            if !isApplyingDetection { pickedSeparator = decimalSeparator }
            if decimalSeparator != oldValue { settingChanged(owner: .columns) }
        }
    }
    public internal(set) var choices = ImportChoices()
    public internal(set) var preview: ImportPreview?
    public var selection: Set<Int> = [] {
        didSet {
            if selection != oldValue {
                reviewState.partition(selection)
                refreshReviewTotals()
            }
        }
    }
    /// Review's and Match's rows, built with each plan (`ImportRowFormatter`).
    var reviewState = ImportReviewState()
    var matchSections = ImportMatchSections()
    /// #60's Will Be Created counts and Totals by Account, built once per plan or tick change, not per redraw.
    var reviewTotals = ImportReviewTotals()
    /// How many times `reviewTotals` was built, for tests (Tech Architect 5648615659 NB1).
    @ObservationIgnored var reviewTotalsBuilds = 0
    /// Counts plans, so only the latest one lands.
    @ObservationIgnored var planGeneration = 0
    /// Whether the latest plan is still running, so dropping it also clears `isWorking`. The sheet turns the
    /// Format pickers off while it's on, so a menu pick can't apply after the plan lands (#232).
    public internal(set) var isPlanning = false
    public internal(set) var receipt: ImportReceipt?
    public internal(set) var isUndone = false
    /// D108, D381.4: the store changed after the import's own change, so Undo Import is no longer offered.
    public internal(set) var isUndoWindowOver = false
    /// D381.4, V1: VoiceOver focus is on Undo Import now. The summary keeps this up to date.
    @ObservationIgnored public var isUndoFocused = false
    /// D381.4, V1: the window ended while VoiceOver focus was on Undo Import or its confirmation was open, so the
    /// summary moves focus to its title. Otherwise focus stays where it is.
    public internal(set) var movesFocusToSummaryTitle = false
    /// D327.1: “Your data changed, so this preview was updated.”, shown inline at the top of the current step
    /// after the preview re-planned because the ledger changed; `nil` otherwise. It isn't an alert.
    public internal(set) var dataChangedNotice: String?
    /// Posts a VoiceOver announcement; the sheet sets `AccessibilityNotification.Announcement`. The data-changed
    /// notice is announced once when it appears, not again while it stays.
    @ObservationIgnored public var announce: (String) -> Void = { _ in }

    @ObservationIgnored let useCases: ImportUseCases
    @ObservationIgnored let defaultCurrency: String
    @ObservationIgnored let locale: Locale
    @ObservationIgnored let timeZone: TimeZone
    @ObservationIgnored let changed: () -> Void
    /// On while a Bulk Edit, or its Undo or Redo, runs in any window: Import and Undo Import wait (D399).
    @ObservationIgnored public var isLedgerBusy: @MainActor () -> Bool = { false }
    /// The shared store-change signal's value now, and its value just after this import's own change (D381.4).
    @ObservationIgnored let revision: @MainActor () -> Int
    @ObservationIgnored var importRevision: Int?
    /// The ledger the preview was planned against. Observed, so the account and match options redraw after a
    /// re-plan (D327.1).
    var ledger = TransactionLedger()
    @ObservationIgnored let money: MoneyFormatter
    /// A date format or decimal separator the user picked; changing a column keeps it (UI Designer #190).
    @ObservationIgnored private var pickedDateOrder: ImportDateOrder?
    @ObservationIgnored private var pickedSeparator: ImportDecimalSeparator?
    @ObservationIgnored private var isApplyingDetection = false
    /// The sheet closed, so late results from work still running are dropped.
    @ObservationIgnored var isClosed = false
    /// The ledger changed while a plan was running; it's checked again when the plan finishes.
    @ObservationIgnored var isDataChangePending = false
    /// What Import awaits after showing “Importing…” so the overlay draws before the save holds the main actor
    /// (Tech Architect NB4 on #190): 32 ms by default, as a `Task.yield()` alone can resume before the next frame.
    @ObservationIgnored let overlayPause: @MainActor () async -> Void
    /// What a plan awaits on the main actor after its background work, before it lands; nothing by default. Tests
    /// hold a plan here to change a setting while it's in flight, without blocking a thread.
    @ObservationIgnored let planPause: @MainActor (ImportReadSettings, ImportChoices) async -> Void

    public init(
        useCases: ImportUseCases,
        defaultCurrency: String,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        changed: @escaping () -> Void = {},
        revision: @escaping @MainActor () -> Int = { 0 },
        overlayPause: @escaping @MainActor () async -> Void = { try? await Task.sleep(for: .milliseconds(32)) },
        planPause: @escaping @MainActor (ImportReadSettings, ImportChoices) async -> Void = { _, _ in },
    ) {
        self.overlayPause = overlayPause
        self.planPause = planPause
        self.useCases = useCases
        self.defaultCurrency = defaultCurrency
        self.locale = locale
        self.timeZone = timeZone
        self.changed = changed
        self.revision = revision
        money = MoneyFormatter(locale: locale)
    }

    // MARK: File

    /// Reads a file the system picker or a drop handed over. Only the name is kept, never the path.
    public func open(url: URL) async {
        let name = url.lastPathComponent
        startWork(ImportExportText.reading)
        let result = await Task.detached { Self.read(url) }.value
        isWorking = false
        switch result {
        case .success(let data):
            await open(data: data, fileName: name)
        case .failure:
            ImportLog.event(.fileUnreadable)
            alert = ImportAlert(title: ImportExportText.couldntOpenTitle(name), message: ImportExportText.unreadable)
        }
    }

    /// The file's bytes, inside its security scope on Apple platforms.
    nonisolated private static func read(_ url: URL) -> Result<Data, any Error> {
        #if canImport(Darwin)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        return Result { try Data(contentsOf: url) }
    }

    public func open(data: Data, fileName: String) async {
        startWork(ImportExportText.reading)
        defer { isWorking = false }
        let pipeline = useCases.pipeline
        let opened = await Task.detached { Result { try pipeline.open(data) } }.value
        guard !isClosed else { return }
        let file: ImportFile
        switch opened {
        case .success(let read):
            file = read
        case .failure(let error):
            ImportLog.event(.fileRefused)
            alert =
                error as? CSVFileError == .notText
                ? ImportAlert(title: ImportExportText.notCSVTitle(fileName), message: ImportExportText.notCSV)
                : ImportAlert(title: ImportExportText.emptyFileTitle(fileName), message: ImportExportText.emptyFile)
            return
        }
        guard file.rowCount > 0 else {
            alert = ImportAlert(title: ImportExportText.noTransactionsTitle, message: ImportExportText.nothingImported)
            return
        }
        do {
            ledger = try useCases.ledger.ledger()
        } catch {
            ImportLog.event(.ledgerUnreadable)
            alert = ImportAlert(
                title: ImportExportText.couldntOpenTitle(fileName),
                message: ImportExportText.loadFailedMessage,
            )
            return
        }
        self.fileName = fileName
        self.file = file
        choices = ImportChoices()
        receipt = nil
        isUndone = false
        pickedDateOrder = nil
        pickedSeparator = nil
        setMapping(file.suggestedMapping)
        step = .columns
        ImportLog.opened(rows: file.rowCount, columns: file.table.header.count)
    }

    /// Whether a tapped reminder must leave the sheet open (S33): from a picked file until the import is done, the
    /// same steps the sheet can't be swiped away on, and on the summary while Undo Import is still offered and
    /// unused. Once Undo Import is used or has ended, the summary is clean again (D382.15, D381.4).
    public var hasUnsavedEdits: Bool {
        step == .summary ? canUndo : step != .pickFile
    }

    /// The current step's name, under the sheet's title.
    public var stepTitle: String {
        switch step {
        case .pickFile, .columns: ImportExportText.columnsStep
        case .account: ImportExportText.accountStep
        case .match: ImportExportText.matchStep
        case .review: ImportExportText.reviewStep
        case .summary: summaryTitle
        }
    }

    public var fileSummary: String {
        ImportExportText.fileSummary(name: fileName, rows: file?.rowCount ?? 0)
    }

    // MARK: Columns

    public func setField(_ field: ImportField?, forColumn column: Int) {
        var changedMapping = mapping
        changedMapping.assign(field, to: column)
        setMapping(changedMapping)
    }

    /// The first rows as they'd be read now: “Row 2” with its date and amount, or its first issue.
    public var previewLines: [(row: String, text: String)] {
        guard let file else { return [] }
        let firstRecords = Array(file.table.records.prefix(3))
        let sample = ImportFile(
            table: CSVTable(delimiter: file.table.delimiter, header: file.table.header, records: firstRecords),
            formatID: file.formatID,
            suggestedMapping: file.suggestedMapping,
        )
        return useCases.pipeline.rows(in: sample, settings: settings)
            .map { row in
                (ImportExportText.row(row.rowNumber), summary(of: row))
            }
    }

    private func setMapping(_ newMapping: ImportColumnMapping) {
        mapping = newMapping
        guard let file else { return }
        let detected = useCases.pipeline.detect(file, mapping: newMapping, locale: locale)
        detection = detected
        isApplyingDetection = true
        dateOrder = pickedDateOrder ?? detected.date.order
        decimalSeparator = pickedSeparator ?? detected.decimalSeparator
        isApplyingDetection = false
        settingChanged(owner: .columns)
    }

    var settings: ImportReadSettings {
        ImportReadSettings(
            mapping: mapping,
            dateOrder: dateOrder,
            decimalSeparator: decimalSeparator,
            timeZone: timeZone,
        )
    }
}

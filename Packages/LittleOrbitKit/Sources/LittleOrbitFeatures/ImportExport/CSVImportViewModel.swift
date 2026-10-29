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
    public private(set) var isWorking = false
    /// What the progress overlay says: reading the file, or saving the import.
    public private(set) var workingText = ImportExportText.reading
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
    public private(set) var preview: ImportPreview?
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
    public private(set) var isPlanning = false
    public private(set) var receipt: ImportReceipt?
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

    private var settings: ImportReadSettings {
        ImportReadSettings(
            mapping: mapping,
            dateOrder: dateOrder,
            decimalSeparator: decimalSeparator,
            timeZone: timeZone,
        )
    }

    // MARK: Target account

    /// Whether the file names no account, so its rows need one chosen.
    public var needsTargetAccount: Bool {
        mapping.column(for: .account) == nil
    }

    public var accountOptions: [ImportMatchOption] {
        ledger.accounts.sorted { $0.sortOrder < $1.sortOrder }.map { ImportMatchOption(id: $0.id, name: $0.name) }
    }

    public var targetAccountID: UUID? {
        get { choices.targetAccountID }
        set {
            choices.targetAccountID = newValue
            settingChanged(owner: needsTargetAccount ? .account : .columns)
        }
    }

    // MARK: Match

    public func setChoice(_ choice: ImportMatchChoice, for key: ImportMatchKey) async {
        choices.matches[key] = choice
        await plan()
    }

    // MARK: Navigation

    public var canGoNext: Bool {
        switch step {
        case .pickFile, .review, .summary: false
        case .columns: canContinueFromColumns
        case .account: choices.targetAccountID != nil
        case .match: preview != nil
        }
    }

    public func next() async {
        guard canGoNext, !isWorking else { return }
        switch step {
        case .columns:
            // Nothing is planned yet, so the latest ledger is read without a notice: the Account step lists the
            // accounts as they are now, even after a change that didn't move the store-change signal.
            if let fresh = try? useCases.ledger.ledger() {
                ledger = fresh
                keepChoicesThatExist(in: fresh)
            }
            if needsTargetAccount {
                step = .account
            } else {
                await planAndContinue()
            }
        case .account:
            await planAndContinue()
        case .match:
            step = .review
        case .pickFile, .review, .summary:
            break
        }
    }

    public func back() {
        switch step {
        case .account: step = .columns
        case .match: step = needsTargetAccount ? .account : .columns
        case .review: step = hasMatchStep ? .match : (needsTargetAccount ? .account : .columns)
        case .pickFile, .columns, .summary: break
        }
    }

    public var canGoBack: Bool {
        [.account, .match, .review].contains(step)
    }

    /// The Match step shows only when the file names something to match.
    private var hasMatchStep: Bool {
        !(preview?.matches.isEmpty ?? true)
    }

    private func planAndContinue() async {
        // A plan dropped because a setting changed while it ran doesn't move the sheet on (B3).
        guard await plan(), preview != nil else { return }
        step = hasMatchStep ? .match : .review
    }

    /// Drops the preview, and any plan still running with the old settings: it won't land or move the sheet on,
    /// and Next is back on for the new settings (Tech Architect B3 on #190).
    func invalidatePreview() {
        planGeneration += 1
        if isPlanning {
            isPlanning = false
            isWorking = false
        }
        preview = nil
        reviewState = ImportReviewState()
        matchSections = ImportMatchSections()
        reviewTotals = ImportReviewTotals()
    }

    /// A read setting or the target account changed: drops the preview and any running plan (B3). A change that
    /// arrives once the sheet has moved on, such as a menu pick applied just after the plan landed, goes back to
    /// the step that owns the setting, so Match or Review is never left empty with Next off (#232), and says so
    /// with the D327.1 notice (UI Designer 6408001553). It's set after the step changes, because a step change
    /// clears it. Review unticks reset to their defaults after a step-back, the same as Back plus a change.
    private func settingChanged(owner: Step) {
        invalidatePreview()
        if step == .match || step == .review {
            step = owner
            let wasShowing = dataChangedNotice != nil
            dataChangedNotice = ImportExportText.dataChanged
            if !wasShowing {
                announce(ImportExportText.dataChanged)
            }
        }
    }

    /// Plans the preview off the main actor, with the Review and Match rows, behind “Reading…”. Only the latest
    /// plan lands: one that a newer plan overtook, such as two quick Match changes, is dropped, and the newest one
    /// clears `isWorking`, so Next and Import stay off until it's in (Tech Architect B2 on #190).
    /// Returns whether this plan landed.
    @discardableResult
    func plan() async -> Bool {
        guard let file else { return false }
        planGeneration += 1
        let generation = planGeneration
        isPlanning = true
        startWork(ImportExportText.reading)
        let pipeline = useCases.pipeline
        let settings = settings
        let ledger = ledger
        let choices = choices
        let currency = defaultCurrency
        let formatter = ImportRowFormatter(
            file: file,
            ledger: ledger,
            settings: settings,
            locale: locale,
            timeZone: timeZone,
            defaultCurrency: currency,
            money: money,
        )
        let planned =
            await Task.detached {
                formatter.plan(
                    pipeline.preview(
                        rows: pipeline.rows(in: file, settings: settings),
                        ledger: ledger,
                        choices: choices,
                        settings: settings,
                        defaultCurrency: currency,
                    )
                )
            }
            .value
        await planPause(settings, choices)
        guard generation == planGeneration else { return false }
        isPlanning = false
        isWorking = false
        guard !isClosed else { return false }
        // Ticks changed during the wait count: the new plan is re-selected against the ticks as they are now
        // (Tech Architect B1 on #190).
        let ticks = Self.reselect(planned.preview, previous: preview, selection: selection)
        var review = planned.review
        review.partition(ticks)
        preview = planned.preview
        reviewState = review
        matchSections = planned.matches
        if selection == ticks {
            refreshReviewTotals()
        }
        selection = ticks
        if isDataChangePending {
            isDataChangePending = false
            await refreshLedger()
        }
        return true
    }

    private func startWork(_ text: String) {
        workingText = text
        isWorking = true
    }

    /// The sheet closed: results of work still running are dropped instead of landing in a dismissed sheet.
    public func close() {
        isClosed = true
    }

    // MARK: Import

    /// Saves the selected rows in one batch, with “Importing…” shown while it runs. The repository is
    /// main-actor bound, so the save itself runs here; it's one batch, about 0.2 s for 5,000 rows.
    ///
    /// D327.1: first it checks the ledger again. If it changed since the last plan, nothing is saved: the preview
    /// re-plans and stays on Review with the notice, so the user sees the new counts before importing.
    public func commit() async {
        guard preview != nil, canImport else { return }
        startWork(ImportExportText.importing)
        defer { isWorking = false }
        isDataChangePending = false
        // Lets the overlay draw before the check and the save hold the main actor (NB4).
        await overlayPause()
        // Cancel is disabled while this runs; if the sheet closed anyway, nothing is saved (NB2 on #190).
        guard !isClosed else { return }
        if await refreshLedger() {
            return
        }
        guard let preview, !isClosed, readyCount > 0 else { return }
        do {
            receipt = try useCases.ledger.commit(preview, selection: selection, fileName: fileName)
            isUndone = false
            isUndoWindowOver = false
            isUndoFocused = false
            movesFocusToSummaryTitle = false
            step = .summary
            changed()
            importRevision = revision()
            ImportLog.imported(receipt?.importedCount ?? 0)
        } catch {
            ImportLog.event(.commitFailed)
            alert = ImportAlert(
                title: ImportExportText.importFailedTitle,
                message: ImportExportText.importFailedMessage,
            )
        }
    }
}

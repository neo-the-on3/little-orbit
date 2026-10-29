import Foundation
import LittleOrbitDomain

/// The work behind “Reading…” and “Importing…”: dropping and planning the preview, closing, and the import's
/// save.
extension CSVImportViewModel {
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
    func settingChanged(owner: Step) {
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
            dateOrder: dateOrder,
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

    func startWork(_ text: String) {
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

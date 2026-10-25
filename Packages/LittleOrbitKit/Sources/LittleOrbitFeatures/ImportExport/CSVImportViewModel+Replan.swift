import Foundation
import LittleOrbitDomain

/// D327.1: re-planning the preview when the data changes while the sheet is open.
extension CSVImportViewModel {
    /// The ticks after a re-plan (D327.1, D42): a row whose status didn't change keeps the user's tick or untick;
    /// a row whose status changed takes its new status's default. So a ticked row that's now Already imported is
    /// unticked and moves to Not Selected, and the user can tick it again.
    nonisolated static func reselect(_ planned: ImportPreview, previous: ImportPreview?, selection: Set<Int>) -> Set<
        Int
    > {
        guard let previous else {
            return planned.defaultSelection
        }
        var before: [Int: ImportRowStatus] = [:]
        for row in previous.rows where before[row.id] == nil {
            before[row.id] = row.status
        }
        var kept = Set<Int>()
        for row in planned.rows where row.isSelectable {
            let unchanged = before[row.id].map { $0.isSameStatus(as: row.status) } ?? false
            if unchanged ? selection.contains(row.id) : row.isSelectedByDefault {
                kept.insert(row.id)
            }
        }
        return kept
    }

    /// D327.1: accounts, categories, payees or transactions changed while the sheet is open, from another window,
    /// a scheduled posting or a watch entry. The sheet calls this on the shared store-change signal. The preview
    /// re-plans with the same mapping, date format, separator, target account and the Match choices that still
    /// exist, and the notice shows. Nothing happens before a file is open or once the import is done.
    public func dataChanged() async {
        guard file != nil, !isClosed, step != .pickFile, step != .summary else { return }
        guard !isWorking else {
            isDataChangePending = true
            return
        }
        await refreshLedger()
    }

    /// Reads the ledger again. When it differs from the one the preview was planned against, re-plans and shows
    /// the notice. Returns whether it changed. A ledger that can't be read leaves the plan as it is; the save
    /// itself still validates every record.
    @discardableResult
    func refreshLedger() async -> Bool {
        guard let fresh = try? useCases.ledger.ledger(), fresh != ledger else { return false }
        ledger = fresh
        keepChoicesThatExist(in: fresh)
        if let id = choices.targetAccountID, !fresh.accounts.contains(where: { $0.id == id }) {
            // The target account has gone: its rows need another one, so the Account step asks again.
            choices.targetAccountID = nil
            invalidatePreview()
            if step == .match || step == .review {
                step = .account
            }
        }
        if preview != nil {
            await plan()
        }
        guard !isClosed else { return true }
        let wasShowing = dataChangedNotice != nil
        dataChangedNotice = ImportExportText.dataChanged
        if !wasShowing {
            announce(ImportExportText.dataChanged)
        }
        return true
    }

    /// Drops Match choices whose existing record has gone, so that name goes back to its automatic match.
    func keepChoicesThatExist(in ledger: TransactionLedger) {
        let accounts = Set(ledger.accounts.filter { $0.deletedAt == nil }.map(\.id))
        let categories = Set(ledger.categories.filter { $0.deletedAt == nil }.map(\.id))
        let payees = Set(ledger.payees.filter { $0.deletedAt == nil }.map(\.id))
        choices.matches = choices.matches.filter { key, choice in
            guard case .existing(let id) = choice else { return true }
            switch key.kind {
            case .account: return accounts.contains(id)
            case .category, .subcategory: return categories.contains(id)
            case .payee: return payees.contains(id)
            }
        }
    }
}

extension ImportRowStatus {
    /// The same kind of status, whichever existing transaction it points to or whichever issues it has.
    fileprivate func isSameStatus(as other: ImportRowStatus) -> Bool {
        switch (self, other) {
        case (.ready, .ready), (.failed, .failed), (.alreadyImported, .alreadyImported),
            (.possibleDuplicate, .possibleDuplicate):
            true
        default:
            false
        }
    }
}

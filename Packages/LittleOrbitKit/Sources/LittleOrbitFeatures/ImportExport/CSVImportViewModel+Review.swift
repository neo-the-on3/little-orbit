import Foundation
import LittleOrbitDomain

/// The Review step and the summary: counts, rows and selection.
extension CSVImportViewModel {
    // MARK: Review

    // The counts and rows are built with the plan and split again when the ticks change (`reviewState`), so
    // drawing Review does no per-row work.

    public var readyCount: Int {
        reviewState.readyCount
    }

    public var failedCount: Int {
        reviewState.failed.count
    }

    public var shortenedCount: Int {
        reviewState.shortenedCount
    }

    public var alreadyImportedCount: Int {
        reviewState.alreadyImportedCount
    }

    public var possibleDuplicateCount: Int {
        reviewState.possibleDuplicateCount
    }

    /// Selected rows.
    public var selectedRows: [ImportReviewRow] {
        reviewState.selected
    }

    /// Importable rows that aren't selected: duplicates by default, and any the user unticked.
    public var unselectedRows: [ImportReviewRow] {
        reviewState.unselected
    }

    public var failedRows: [ImportReviewRow] {
        reviewState.failed
    }

    public func toggle(_ id: Int) {
        guard preview?.rows.contains(where: { $0.id == id && $0.isSelectable }) == true else { return }
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    public var importTitle: String {
        ImportExportText.importButton(readyCount)
    }

    /// The Review toolbar's one Import: “Import” on iOS, where the summary shows the count, and the sheet's
    /// default button “Import N Transactions” on the Mac (UI Designer, 26 Oct).
    public func importActionTitle(on platform: ImportExportPlatform) -> String {
        platform == .mac ? importTitle : ImportExportText.importAction
    }

    /// The note under Review's counts: tap on iOS, click on the Mac (D367).
    public func reviewFooter(on platform: ImportExportPlatform) -> String {
        platform == .mac ? ImportExportText.nothingSavedMac : ImportExportText.nothingSaved
    }

    public var canImport: Bool {
        step == .review && readyCount > 0 && !isWorking
    }

    /// A row issue in the file format's wording.
    func issueText(_ issue: ImportRowIssue) -> String {
        ImportRowFormatter.issueText(issue, debitAndCredit: isDebitAndCredit, dateOrder: dateOrder)
    }

    // MARK: Debit & Credit preview (#60)

    /// The footer under Not Selected: #60 compares fewer fields and counts shortened notes (D324.2).
    public var notSelectedFooter: String {
        isDebitAndCredit ? ImportExportText.debitAndCreditNotSelectedFooter : ImportExportText.notSelectedFooter
    }

    /// The new accounts, categories and payees the ticked rows need, shown before anything is saved (#60).
    public var createdCounts: ImportCreatedCounts {
        reviewTotals.created
    }

    /// Income and expense of the ticked rows per account, each in its own currency, transfers left out (#60).
    public var accountTotals: [ImportAccountTotalRow] {
        reviewTotals.accounts
    }

    /// Builds `reviewTotals` again for the current plan and ticks: when a plan lands or the ticks change, so
    /// drawing Review reads stored values (Tech Architect 5648615659 NB1). Only Debit & Credit shows them.
    func refreshReviewTotals() {
        guard isDebitAndCredit, let preview else {
            reviewTotals = ImportReviewTotals()
            return
        }
        reviewTotalsBuilds += 1
        reviewTotals = ImportReviewTotals(created: preview.created(selection), accounts: accountTotals(of: preview))
    }

    private func accountTotals(of preview: ImportPreview) -> [ImportAccountTotalRow] {
        let accounts = Dictionary(ledger.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return preview.totals(selection)
            .map { total in
                let name: String
                let currency: String
                switch total.account {
                case .existing(let id):
                    let account = accounts[id]
                    name = account?.name ?? ""
                    currency = account?.currencyCode ?? defaultCurrency
                case .new(let key):
                    let match = preview.matches.first { $0.key == key }
                    name = match?.name ?? ""
                    currency = match?.currencyCode ?? defaultCurrency
                }
                return ImportAccountTotalRow(
                    id: total.account,
                    name: name,
                    currencyCode: currency,
                    income: money.string(total.income, currencyCode: currency),
                    expense: money.string(-total.expense, currencyCode: currency),
                )
            }
    }

    func summary(of row: ImportRow) -> String {
        if let issue = row.issues.first {
            return issueText(issue)
        }
        var parts: [String] = []
        if let date = row.date {
            parts.append(
                date.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone)
                )
            )
        }
        if let amount = row.amount {
            let signed = row.kind == .expense ? -amount : amount
            parts.append(money.string(signed, currencyCode: row.currencyCode ?? defaultCurrency))
        }
        if let title = row.payee ?? row.details {
            parts.append(title)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Summary

    public var summaryTitle: String {
        isUndone ? ImportExportText.undoneTitle : ImportExportText.importComplete
    }

    /// “6 transactions imported”; after Undo Import, the confirmation's sentence naming the file, so the
    /// summary no longer says anything was imported.
    public var importedText: String {
        if isUndone, let receipt {
            return ImportExportText.removedFromFile(receipt.fileName)
        }
        return ImportExportText.imported(receipt?.importedCount ?? 0)
    }

    /// The Also Created lines: “2 new accounts”, “5 new categories”, “12 new payees”.
    public var createdLines: [String] {
        guard let receipt, !isUndone else { return [] }
        var lines: [String] = []
        if !receipt.createdAccounts.isEmpty {
            lines.append(ImportExportText.createdAccounts(receipt.createdAccounts.count))
        }
        if !receipt.createdCategories.isEmpty {
            lines.append(ImportExportText.createdCategories(receipt.createdCategories.count))
        }
        if !receipt.createdPayees.isEmpty {
            lines.append(ImportExportText.createdPayees(receipt.createdPayees.count))
        }
        return lines
    }

    /// The Rows Not Imported lines, with counts: can't import, not selected (rows the user unticked), already
    /// imported, possible duplicates. “Not selected” is a count, so it's in sentence case (D327.4); Review's
    /// section title stays “Not Selected”.
    public var notImportedLines: [(label: String, count: Int)] {
        guard let receipt else { return [] }
        return [
            (ImportExportText.cantImport, receipt.failed),
            (ImportExportText.notSelectedCount, receipt.skippedOther),
            (ImportExportText.alreadyImported, receipt.skippedAlreadyImported),
            (ImportExportText.possibleDuplicates, receipt.skippedPossibleDuplicates),
        ]
        .filter { $0.count > 0 }
    }

    /// D286: the note about refunds imported without a link, or `nil`.
    public var unlinkedRefundNote: String? {
        guard let count = receipt?.unlinkedRefundCount, count > 0, !isUndone else { return nil }
        return ImportExportText.unlinkedRefunds(count)
    }

    public var canUndo: Bool {
        step == .summary && receipt.map { !$0.transactions.isEmpty } == true && !isUndone && !isUndoWindowOver
            && !isWorking
    }

    public var undoTitle: String {
        ImportExportText.undoTitle(receipt?.importedCount ?? 0)
    }

    /// D281 and D323.8: names the file, then lists only what the import created.
    public var undoMessage: String {
        guard let receipt else { return "" }
        var created: [String] = []
        if receipt.createdAccounts.count == 1, let account = receipt.createdAccounts.first {
            created.append(ImportExportText.createdAccount(named: account.name))
        } else if !receipt.createdAccounts.isEmpty {
            created.append(ImportExportText.createdAccounts(receipt.createdAccounts.count))
        }
        if !receipt.createdCategories.isEmpty {
            created.append(ImportExportText.createdCategories(receipt.createdCategories.count))
        }
        if !receipt.createdPayees.isEmpty {
            created.append(ImportExportText.createdPayees(receipt.createdPayees.count))
        }
        return ImportExportText.undoMessage(fileName: receipt.fileName, created: created, locale: locale)
    }
}

import Foundation
import LittleOrbitDomain

/// The Review step and the summary: counts, rows and selection.
extension CSVImportViewModel {
    // MARK: Review

    public var readyCount: Int {
        preview?.importable(selection).count ?? 0
    }

    public var failedCount: Int {
        preview?.failedCount ?? 0
    }

    public var shortenedCount: Int {
        guard let preview else { return 0 }
        return preview.importable(selection).filter { !$0.row.warnings.isEmpty }.count
    }

    public var alreadyImportedCount: Int {
        preview?.alreadyImportedCount ?? 0
    }

    public var possibleDuplicateCount: Int {
        preview?.possibleDuplicateCount ?? 0
    }

    /// Selected rows.
    public var selectedRows: [ImportReviewRow] {
        reviewRows { $0.isSelectable && selection.contains($0.id) }
    }

    /// Importable rows that aren't selected: duplicates by default, and any the user unticked.
    public var unselectedRows: [ImportReviewRow] {
        reviewRows { $0.isSelectable && !selection.contains($0.id) }
    }

    public var failedRows: [ImportReviewRow] {
        reviewRows { !$0.isSelectable }
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

    public var canImport: Bool {
        step == .review && readyCount > 0 && !isWorking
    }

    private func reviewRows(_ include: (ImportPreviewRow) -> Bool) -> [ImportReviewRow] {
        (preview?.rows ?? []).filter(include).map(reviewRow)
    }

    private func reviewRow(_ row: ImportPreviewRow) -> ImportReviewRow {
        let input = row.row
        let title = input.payee ?? input.details ?? input.category?.name ?? input.accountName ?? ""
        var detail = [ImportExportText.row(input.rowNumber)]
        if let date = input.date {
            detail.append(
                date.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone)
                )
            )
        }
        if let account = draftAccountName(row) {
            detail.append(account)
        }
        let currency = draftCurrency(row)
        let signed = input.kind == .expense ? -(input.amount ?? 0) : (input.amount ?? 0)
        let amount = input.amount.map { _ in money.string(signed, currencyCode: currency) } ?? ""
        return ImportReviewRow(
            id: row.id,
            title: title,
            detail: detail.joined(separator: " · "),
            amount: amount,
            tone: tone(of: input.kind),
            message: message(for: row),
            messageStyle: messageStyle(for: row),
            source: source(for: row),
            isSelectable: row.isSelectable,
        )
    }

    private func tone(of kind: ImportRowKind?) -> AmountTone {
        switch kind {
        case .expense?: .negative
        case .income?, .refund?: .positive
        case .transfer?: .transfer
        case nil: .neutral
        }
    }

    private func message(for row: ImportPreviewRow) -> String? {
        switch row.status {
        case .failed(let issues):
            return issues.first.map { ImportExportText.issue($0, dateOrder: dateOrder) }
        case .alreadyImported:
            return ImportExportText.alreadyImported
        case .possibleDuplicate:
            return ImportExportText.possibleDuplicate
        case .ready:
            return row.row.warnings.first.map(ImportExportText.warning)
        }
    }

    private func messageStyle(for row: ImportPreviewRow) -> ImportReviewMessageStyle {
        switch row.status {
        case .failed: .error
        case .alreadyImported: .secondary
        case .possibleDuplicate, .ready: .warning
        }
    }

    /// The column and raw value the row's first issue is about, when it's about one cell (D323.3, D349.1). An
    /// unclosed quote names only its column, as its value runs to the end of the file (D349.2).
    private func source(for row: ImportPreviewRow) -> String? {
        guard case .failed(let issues) = row.status, let file, let column = row.row.issueColumn,
            issues.first == row.row.issues.first, file.table.header.indices.contains(column)
        else {
            return nil
        }
        if issues.first == .unclosedQuote {
            return file.table.header[column]
        }
        let records = file.table.records
        let guess = row.row.rowNumber - 2
        let record =
            records.indices.contains(guess) && records[guess].rowNumber == row.row.rowNumber
            ? records[guess] : records.first { $0.rowNumber == row.row.rowNumber }
        guard let value = ImportText.value(record?.field(column)) else {
            return nil
        }
        return ImportExportText.issueSource(column: file.table.header[column], value: value)
    }

    private func draftAccountName(_ row: ImportPreviewRow) -> String? {
        switch row.draft?.account {
        case .existing(let id)?: ledger.accounts.first { $0.id == id }?.name
        case .new?: row.row.accountName
        case nil: row.row.accountName
        }
    }

    private func draftCurrency(_ row: ImportPreviewRow) -> String {
        if case .existing(let id)? = row.draft?.account, let account = ledger.accounts.first(where: { $0.id == id }) {
            return account.currencyCode
        }
        return row.row.currencyCode ?? defaultCurrency
    }

    func summary(of row: ImportRow) -> String {
        if let issue = row.issues.first {
            return ImportExportText.issue(issue, dateOrder: dateOrder)
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

    public var importedText: String {
        ImportExportText.imported(isUndone ? 0 : receipt?.importedCount ?? 0)
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
        step == .summary && receipt.map { !$0.transactions.isEmpty } == true && !isUndone && !isWorking
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

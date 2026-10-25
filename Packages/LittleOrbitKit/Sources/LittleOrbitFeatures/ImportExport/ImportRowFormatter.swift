import Foundation
import LittleOrbitDomain

/// One Review row, formatted once per plan, with what its section and counts need.
struct ImportReviewEntry: Equatable, Sendable {
    let row: ImportReviewRow
    let hasWarnings: Bool
}

/// Review's rows and counts, built once per plan and split again only when the ticks change, so drawing the
/// step does no per-row work, however long the file (Tester's 5,200-row Mac pass on #190).
struct ImportReviewState: Equatable, Sendable {
    private(set) var entries: [ImportReviewEntry] = []
    private(set) var selected: [ImportReviewRow] = []
    private(set) var unselected: [ImportReviewRow] = []
    private(set) var failed: [ImportReviewRow] = []
    private(set) var readyCount = 0
    private(set) var shortenedCount = 0
    private(set) var alreadyImportedCount = 0
    private(set) var possibleDuplicateCount = 0

    init() {}

    /// The rows and their fixed counts, not yet split by the ticks.
    init(preview: ImportPreview, entries: [ImportReviewEntry]) {
        self.entries = entries
        for row in preview.rows {
            switch row.status {
            case .alreadyImported: alreadyImportedCount += 1
            case .possibleDuplicate: possibleDuplicateCount += 1
            case .ready, .failed: break
            }
        }
    }

    /// Splits the rows by the ticks: one pass, set lookups only.
    mutating func partition(_ selection: Set<Int>) {
        selected = []
        unselected = []
        failed = []
        shortenedCount = 0
        for entry in entries {
            if !entry.row.isSelectable {
                failed.append(entry.row)
            } else if selection.contains(entry.row.id) {
                selected.append(entry.row)
                if entry.hasWarnings {
                    shortenedCount += 1
                }
            } else {
                unselected.append(entry.row)
            }
        }
        readyCount = selected.count
    }
}

/// The Match step's rows by section, built once per plan.
struct ImportMatchSections: Equatable, Sendable {
    var accounts: [ImportMatchRow] = []
    var categories: [ImportMatchRow] = []
    var payees: [ImportMatchRow] = []
}

/// Formats a plan's Review and Match rows. It's a value with no main-actor state, so it runs with the plan off
/// the main actor; each list of options is sorted once, not once per row, and accounts are looked up by id.
struct ImportRowFormatter: Sendable {
    let file: ImportFile
    let ledger: TransactionLedger
    let dateOrder: ImportDateOrder
    let defaultCurrency: String
    let money: MoneyFormatter
    let dateStyle: Date.FormatStyle
    private let accountsByID: [UUID: Account]

    init(
        file: ImportFile,
        ledger: TransactionLedger,
        dateOrder: ImportDateOrder,
        locale: Locale,
        timeZone: TimeZone,
        defaultCurrency: String,
        money: MoneyFormatter,
    ) {
        self.file = file
        self.ledger = ledger
        self.dateOrder = dateOrder
        self.defaultCurrency = defaultCurrency
        self.money = money
        dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone)
        accountsByID = Dictionary(ledger.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// A finished plan: the preview and the rows Review and Match show. The ticks are chosen on the main actor
    /// when it lands, against the ticks as they are then (`ImportReviewState.partition`).
    struct Planned: Sendable {
        let preview: ImportPreview
        let review: ImportReviewState
        let matches: ImportMatchSections
    }

    func plan(_ preview: ImportPreview) -> Planned {
        Planned(preview: preview, review: review(preview), matches: matches(preview))
    }

    // MARK: Review

    func review(_ preview: ImportPreview) -> ImportReviewState {
        let records = recordIndex()
        let entries = preview.rows.map { row in
            ImportReviewEntry(
                row: reviewRow(row, records: records),
                hasWarnings: row.isSelectable && !row.row.warnings.isEmpty,
            )
        }
        return ImportReviewState(preview: preview, entries: entries)
    }

    /// Each record's position by its row number, for the D349 source line.
    private func recordIndex() -> [Int: Int] {
        var index: [Int: Int] = [:]
        for (position, record) in file.table.records.enumerated() where index[record.rowNumber] == nil {
            index[record.rowNumber] = position
        }
        return index
    }

    private func reviewRow(_ row: ImportPreviewRow, records: [Int: Int]) -> ImportReviewRow {
        let input = row.row
        let title = input.payee ?? input.details ?? input.category?.name ?? input.accountName ?? ""
        var detail = [ImportExportText.row(input.rowNumber)]
        if let date = input.date {
            detail.append(date.formatted(dateStyle))
        }
        let account = draftAccount(row)
        if let name = draftAccountName(row, account: account) {
            detail.append(name)
        }
        let currency = account?.currencyCode ?? input.currencyCode ?? defaultCurrency
        let signed = input.kind == .expense ? -(input.amount ?? 0) : (input.amount ?? 0)
        let amount = input.amount.map { _ in money.string(signed, currencyCode: currency) } ?? ""
        return ImportReviewRow(
            id: row.id,
            title: title,
            detail: detail.joined(separator: " · "),
            amount: amount,
            tone: Self.tone(of: input.kind),
            message: message(for: row),
            messageStyle: Self.messageStyle(for: row),
            source: source(for: row, records: records),
            isSelectable: row.isSelectable,
        )
    }

    private func draftAccount(_ row: ImportPreviewRow) -> Account? {
        guard case .existing(let id)? = row.draft?.account else { return nil }
        return accountsByID[id]
    }

    /// An existing account's name, or the file's name for a new one or none.
    private func draftAccountName(_ row: ImportPreviewRow, account: Account?) -> String? {
        if case .existing? = row.draft?.account {
            return account?.name
        }
        return row.row.accountName
    }

    private static func tone(of kind: ImportRowKind?) -> AmountTone {
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
            issues.first.map { ImportExportText.issue($0, dateOrder: dateOrder) }
        case .alreadyImported:
            ImportExportText.alreadyImported
        case .possibleDuplicate:
            ImportExportText.possibleDuplicate
        case .ready:
            row.row.warnings.first.map(ImportExportText.warning)
        }
    }

    private static func messageStyle(for row: ImportPreviewRow) -> ImportReviewMessageStyle {
        switch row.status {
        case .failed: .error
        case .alreadyImported: .secondary
        case .possibleDuplicate, .ready: .warning
        }
    }

    /// The column and raw value the row's first issue is about, when it's about one cell (D323.3, D349.1). An
    /// unclosed quote names only its column, as its value runs to the end of the file (D349.2).
    private func source(for row: ImportPreviewRow, records: [Int: Int]) -> String? {
        guard case .failed(let issues) = row.status, let column = row.row.issueColumn,
            issues.first == row.row.issues.first, file.table.header.indices.contains(column)
        else {
            return nil
        }
        if issues.first == .unclosedQuote {
            return file.table.header[column]
        }
        let record = records[row.row.rowNumber].map { file.table.records[$0] }
        guard let value = ImportText.value(record?.field(column)) else {
            return nil
        }
        return ImportExportText.issueSource(column: file.table.header[column], value: value)
    }

    // MARK: Match

    func matches(_ preview: ImportPreview) -> ImportMatchSections {
        var options: [ImportMatchKind: [ImportMatchOption]] = [:]
        var sections = ImportMatchSections()
        for match in preview.matches {
            let kind = Self.optionsKind(match.key.kind)
            let list = options[kind] ?? self.options(for: kind)
            options[kind] = list
            let row = ImportMatchRow(
                id: match.key,
                name: match.parentName.map { ImportExportText.categoryPath(parent: $0, name: match.name) }
                    ?? match.name,
                choice: match.choice,
                options: list,
            )
            switch match.key.kind {
            case .account: sections.accounts.append(row)
            case .category, .subcategory: sections.categories.append(row)
            case .payee: sections.payees.append(row)
            }
        }
        return sections
    }

    /// Every subcategory of a kind is offered whatever the file's parent, so they share one list.
    private static func optionsKind(_ kind: ImportMatchKind) -> ImportMatchKind {
        if case .subcategory(let categoryKind, _) = kind {
            return .subcategory(categoryKind, parentKey: "")
        }
        return kind
    }

    private func options(for kind: ImportMatchKind) -> [ImportMatchOption] {
        switch kind {
        case .account:
            return ledger.accounts.sorted { $0.sortOrder < $1.sortOrder }
                .map { ImportMatchOption(id: $0.id, name: $0.name) }
        case .category(let categoryKind):
            return ledger.categories.filter { $0.kind == categoryKind && $0.parentID == nil && !$0.isArchived }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { ImportMatchOption(id: $0.id, name: $0.name) }
        case .subcategory(let categoryKind, _):
            let parents = Dictionary(
                ledger.categories.map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first },
            )
            return ledger.categories.filter { $0.kind == categoryKind && $0.parentID != nil && !$0.isArchived }
                .map { category in
                    let parent = category.parentID.flatMap { parents[$0] } ?? ""
                    return ImportMatchOption(
                        id: category.id,
                        name: ImportExportText.categoryPath(parent: parent, name: category.name),
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .payee:
            return ledger.payees.filter { !$0.isArchived }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { ImportMatchOption(id: $0.id, name: $0.name) }
        }
    }
}

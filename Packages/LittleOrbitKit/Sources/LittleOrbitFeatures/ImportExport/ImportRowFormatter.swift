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
    /// Whether a column is mapped to Currency. Without one, a new account asks for its currency (D453.1).
    let readsCurrency: Bool
    let defaultCurrency: String
    let money: MoneyFormatter
    let dateStyle: Date.FormatStyle
    private let accountsByID: [UUID: Account]

    init(
        file: ImportFile,
        ledger: TransactionLedger,
        settings: ImportReadSettings,
        locale: Locale,
        timeZone: TimeZone,
        defaultCurrency: String,
        money: MoneyFormatter,
    ) {
        self.file = file
        self.ledger = ledger
        dateOrder = settings.dateOrder
        readsCurrency = settings.mapping.column(for: .currency) != nil
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
        let newCurrencies = newAccountCurrencies(preview)
        let entries = preview.rows.map { row in
            ImportReviewEntry(
                row: reviewRow(row, records: records, newCurrencies: newCurrencies),
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

    /// Whether the file is a Debit & Credit export (#60): its own wording, reasons and new-account currencies.
    private var isDebitAndCredit: Bool {
        file.formatID == DebitAndCreditFormat.formatID
    }

    /// A row issue in the file format's wording.
    static func issueText(_ issue: ImportRowIssue, debitAndCredit: Bool, dateOrder: ImportDateOrder) -> String {
        debitAndCredit
            ? ImportExportText.debitAndCreditIssue(issue) : ImportExportText.issue(issue, dateOrder: dateOrder)
    }

    private func issueText(_ issue: ImportRowIssue) -> String {
        Self.issueText(issue, debitAndCredit: isDebitAndCredit, dateOrder: dateOrder)
    }

    /// The currency each new account gets (the file's, the one picked on the Match step, or the default), by
    /// its match, looked up once per plan rather than once per row.
    private func newAccountCurrencies(_ preview: ImportPreview) -> [ImportMatchKey: String?] {
        Dictionary(preview.matches.map { ($0.key, $0.currencyCode) }, uniquingKeysWith: { first, _ in first })
    }

    private func reviewRow(
        _ row: ImportPreviewRow,
        records: [Int: Int],
        newCurrencies: [ImportMatchKey: String?],
    ) -> ImportReviewRow {
        let input = row.row
        let title = input.payee ?? input.details ?? input.category?.name ?? input.accountName ?? ""
        // A transfer the planner paired names both rows (#60).
        let rows =
            input.mergedRowNumbers.first.map { ImportExportText.pairedRows(input.rowNumber, $0) }
            ?? ImportExportText.row(input.rowNumber)
        var detail = [rows]
        if let date = input.date {
            detail.append(date.formatted(dateStyle))
        }
        let account = draftAccount(row)
        if let name = draftAccountName(row, account: account) {
            detail.append(name)
        }
        if let received = receivedText(row, newCurrencies) {
            detail.append(received)
        }
        let currency =
            account?.currencyCode ?? newAccountCurrency(row, newCurrencies) ?? input.currencyCode
            ?? defaultCurrency
        let signed = input.kind == .expense ? -(input.amount ?? 0) : (input.amount ?? 0)
        let amount = input.amount.map { _ in money.string(signed, currencyCode: currency) } ?? ""
        let message = message(for: row)
        return ImportReviewRow(
            id: row.id,
            title: title,
            detail: detail.joined(separator: " · "),
            amount: amount,
            tone: Self.tone(of: input.kind),
            message: message,
            reasons: isDebitAndCredit && !row.issues.isEmpty ? row.issues.map(issueText) : message.map { [$0] } ?? [],
            messageStyle: Self.messageStyle(for: row),
            source: source(for: row, records: records),
            isSelectable: row.isSelectable,
        )
    }

    /// “received €5,000.00” on a Debit & Credit transfer between currencies, as a transfer row says it (D17,
    /// #30 S90): the amount the merged incoming half gives (D330.1), in the receiving account's currency.
    private func receivedText(_ row: ImportPreviewRow, _ currencies: [ImportMatchKey: String?]) -> String? {
        guard isDebitAndCredit, let draft = row.draft, let received = draft.destinationAmount else { return nil }
        let currency: String
        switch draft.toAccount {
        case .existing(let id)?:
            currency = accountsByID[id]?.currencyCode ?? defaultCurrency
        case .new(let key)?:
            currency = (currencies[key] ?? nil) ?? defaultCurrency
        case nil:
            return nil
        }
        return ImportExportText.received(money.string(received, currencyCode: currency))
    }

    /// A new account's currency from the Match step, when the row's draft creates one.
    private func newAccountCurrency(_ row: ImportPreviewRow, _ currencies: [ImportMatchKey: String?]) -> String? {
        guard case .new(let key)? = row.draft?.account else { return nil }
        return currencies[key] ?? nil
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
            issues.first.map(issueText)
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
                newAccountCurrency: newAccountCurrency(match),
                // Both halves of a transfer count, so a re-plan doesn't change it (#60 plan step 3).
                detail: isDebitAndCredit ? ImportExportText.rowCount(match.rowCount) : nil,
            )
            switch match.key.kind {
            case .account: sections.accounts.append(row)
            case .category, .subcategory: sections.categories.append(row)
            case .payee: sections.payees.append(row)
            }
        }
        return sections
    }

    /// A new account asks for its currency in a Debit & Credit file (#60) and in any file with no currency
    /// column (D453.1); otherwise the file names it. It starts at the device locale's currency (D387.3).
    private func newAccountCurrency(_ match: ImportMatch) -> String? {
        guard isDebitAndCredit || !readsCurrency, case .account = match.key.kind, match.choice == .new else {
            return nil
        }
        return match.currencyCode ?? defaultCurrency
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

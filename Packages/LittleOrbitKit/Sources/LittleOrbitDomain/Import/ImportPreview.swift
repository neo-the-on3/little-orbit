import Foundation

/// A row resolved against the ledger, ready to be saved.
public struct ImportDraft: Equatable, Sendable {
    public var kind: ImportRowKind
    public var date: Date
    public var timeZoneID: String
    public var amount: Decimal
    /// Only for a transfer between currencies; `nil` otherwise, as the ledger stores it.
    public var destinationAmount: Decimal?
    public var account: ImportRef
    public var toAccount: ImportRef?
    public var category: ImportRef?
    public var payee: ImportRef?
    public var details: String?
    public var note: String?
}

/// Where a row stands in Review.
public enum ImportRowStatus: Equatable, Sendable {
    /// Imported unless the user unticks it.
    case ready
    /// Can't be imported or ticked; the reasons are in column order.
    case failed([ImportRowIssue])
    /// Same account, moment, amount and type, category, payee, description and notes as this transaction:
    /// “Already imported”, unticked (D42).
    case alreadyImported(existingID: UUID)
    /// Same account, amount and type within ±3 days and a matching payee or description: “Possible duplicate”,
    /// unticked (D18, D28, D42).
    case possibleDuplicate(existingID: UUID)
}

public struct ImportPreviewRow: Equatable, Sendable, Identifiable {
    public var row: ImportRow
    public var status: ImportRowStatus
    public var draft: ImportDraft?

    public var id: Int {
        row.rowNumber
    }

    /// Error rows can't be ticked.
    public var isSelectable: Bool {
        draft != nil
    }

    /// Only ready rows start ticked; duplicates start unticked (D18, D42).
    public var isSelectedByDefault: Bool {
        status == .ready
    }

    public var issues: [ImportRowIssue] {
        if case .failed(let issues) = status {
            return issues
        }
        return []
    }
}

/// Everything Review shows before anything is saved (#30, #60 “Preview”).
public struct ImportPreview: Equatable, Sendable {
    public var rows: [ImportPreviewRow]
    public var matches: [ImportMatch]

    public init(rows: [ImportPreviewRow], matches: [ImportMatch]) {
        self.rows = rows
        self.matches = matches
    }

    public var defaultSelection: Set<Int> {
        Set(rows.filter(\.isSelectedByDefault).map(\.id))
    }

    public var failedCount: Int {
        rows.filter { !$0.isSelectable }.count
    }

    public var alreadyImportedCount: Int {
        rows.filter { if case .alreadyImported = $0.status { true } else { false } }.count
    }

    public var possibleDuplicateCount: Int {
        rows.filter { if case .possibleDuplicate = $0.status { true } else { false } }.count
    }

    /// Rows that import with a warning count in “To import” too; this is the separate warning count (D114).
    public var shortenedCount: Int {
        rows.filter { $0.isSelectable && !$0.row.warnings.isEmpty }.count
    }

    /// The selectable rows among `selection`.
    public func importable(_ selection: Set<Int>) -> [ImportPreviewRow] {
        rows.filter { $0.isSelectable && selection.contains($0.id) }
    }
}

/// Matches rows to the ledger, checks them against the account's currency and the transfer rules, and flags
/// duplicates. It's pure, so it runs off the main actor for big files (#30 S35).
public enum ImportPlanner {
    public static func preview(
        rows: [ImportRow],
        ledger: TransactionLedger,
        choices: ImportChoices,
        timeZone: TimeZone,
        defaultCurrency: String,
    ) -> ImportPreview {
        var matcher = ImportMatcher(ledger: ledger, choices: choices, defaultCurrency: defaultCurrency)
        let target = choices.targetAccountID.flatMap { id in ledger.accounts.first { $0.id == id } }
        let pairing = pairTransfers(rows, matcher: matcher, target: target)
        var resolved: [(ImportRow, ImportDraft?)] = []
        resolved.reserveCapacity(rows.count)
        for (index, input) in rows.enumerated() {
            var row = input
            switch pairing[index] {
            case .absorbed?:
                // Its names still count on the Match step, so a re-plan doesn't change the list (D327, D330).
                registerAccounts(of: row, matcher: &matcher)
                continue
            case .merged(let merged)?:
                row = merged
            case .failed(let issue)?:
                row.issues.append(issue)
                row.issues = row.issuesInFieldOrder(row.issues)
                if row.issues.first == issue {
                    row.issueColumn = issue.field.flatMap { row.transferColumns[$0] }
                }
            case nil:
                break
            }
            resolved.append(resolve(row, matcher: &matcher, target: target, timeZone: timeZone))
        }
        let detector = ImportDuplicateDetector(ledger: ledger, timeZone: timeZone)
        let previewRows = resolved.map { row, draft -> ImportPreviewRow in
            guard let draft else {
                return ImportPreviewRow(row: row, status: .failed(row.issues), draft: nil)
            }
            return ImportPreviewRow(row: row, status: detector.status(of: draft, row: row), draft: draft)
        }
        return ImportPreview(rows: previewRows, matches: matcher.orderedMatches)
    }

    /// The transfer halves a format left for pairing (#60), paired against the accounts matching resolves them
    /// to (D330). A copy of the matcher makes the same calls in the same order as the real pass, so the
    /// accounts and new accounts' currencies are the ones the drafts get.
    private static func pairTransfers(
        _ rows: [ImportRow],
        matcher: ImportMatcher,
        target: Account?,
    ) -> [Int: ImportTransferPairing.Outcome] {
        guard rows.contains(where: { $0.transferHalf != nil }) else {
            return [:]
        }
        var probe = matcher
        let refs = rows.map { row in registerAccounts(of: row, matcher: &probe, target: target) }
        return ImportTransferPairing.outcomes(
            rows,
            accounts: ImportTransferPairing.Accounts(refs: refs, currency: { probe.currency(of: $0) }),
        )
    }

    /// The accounts `resolve` would match for the row, noted with the matcher in the same order.
    @discardableResult
    private static func registerAccounts(
        of row: ImportRow,
        matcher: inout ImportMatcher,
        target: Account? = nil,
    ) -> (source: ImportRef?, destination: ImportRef?) {
        let source: ImportRef? =
            if let name = row.accountName {
                matcher.account(named: name, currency: row.currencyCode)
            } else {
                target.map { .existing($0.id) }
            }
        var destination: ImportRef?
        if row.kind == .transfer, let name = row.toAccountName {
            destination = matcher.account(named: name, currency: nil)
        }
        return (source, destination)
    }

    /// Puts the file's and matching's issues in the format's order, then names the cell behind the first reason
    /// (D349.1). When ordering puts a different reason first than the one its cell was found for, no file value
    /// goes under it.
    private static func settle(
        _ row: inout ImportRow,
        input: ImportRow,
        issues: [ImportRowIssue],
        found: [(issue: ImportRowIssue, column: Int?)],
    ) {
        row.issues = row.issuesInFieldOrder(issues)
        row.issueColumn = issueColumn(of: input, found: found, issues: row.issues)
    }

    private static func resolve(
        _ input: ImportRow,
        matcher: inout ImportMatcher,
        target: Account?,
        timeZone: TimeZone,
    ) -> (ImportRow, ImportDraft?) {
        var row = input
        var issues = row.issues
        // The cells behind the reasons found here, in the order they're added (D349.1).
        var found: [(issue: ImportRowIssue, column: Int?)] = []
        let account: ImportRef? =
            if let name = row.accountName {
                matcher.account(named: name, currency: row.currencyCode)
            } else {
                target.map { .existing($0.id) }
            }
        if account == nil && !issues.contains(.missingAccount) {
            issues.insert(.missingAccount, at: 0)
        }
        var toAccount: ImportRef?
        if row.kind == .transfer, let name = row.toAccountName {
            toAccount = matcher.account(named: name, currency: nil)
        }
        var category: ImportRef?
        if let path = row.category, let kind = row.kind?.categoryKind {
            category = matcher.category(path, kind: kind)
        }
        let payee = row.kind == .transfer ? nil : row.payee.map { matcher.payee(named: $0) }
        var destination: Decimal?
        if let account {
            let currency = matcher.currency(of: account)
            if let fileCurrency = row.currencyCode, fileCurrency != currency {
                found.append((.currencyMismatch(accountCurrency: currency), row.columns.currency))
            }
            if let amount = row.amount, !fits(amount, currency) {
                found.append((.tooManyDecimalPlaces(currencyCode: currency), row.columns.amount))
            }
            if let toAccount {
                destination = checkTransfer(row, from: account, to: toAccount, matcher: matcher, found: &found)
            }
        }
        issues += found.map(\.issue)
        settle(&row, input: input, issues: issues, found: found)
        guard row.issues.isEmpty, let kind = row.kind, let date = row.date, let amount = row.amount, let account else {
            if row.issues.isEmpty {
                row.issues = [.missingAmount]
            }
            return (row, nil)
        }
        let draft = ImportDraft(
            kind: kind,
            date: date,
            timeZoneID: timeZone.identifier,
            amount: amount,
            destinationAmount: destination,
            account: account,
            toAccount: toAccount,
            category: category,
            payee: payee,
            details: row.details,
            note: row.note,
        )
        return (row, draft)
    }

    /// The transfer rules: two different accounts (D50, D108), and Destination Amount per D29. Returns the
    /// destination amount to store, `nil` for one currency.
    private static func checkTransfer(
        _ row: ImportRow,
        from account: ImportRef,
        to toAccount: ImportRef,
        matcher: ImportMatcher,
        found: inout [(issue: ImportRowIssue, column: Int?)],
    ) -> Decimal? {
        if account == toAccount {
            found.append((.sameTransferAccount, row.columns.toAccount))
            return nil
        }
        let source = matcher.currency(of: account)
        let destination = matcher.currency(of: toAccount)
        if source == destination {
            if let received = row.destinationAmount, received != row.amount {
                found.append((.destinationAmountMismatch, nil))
            }
            return nil
        }
        guard let received = row.destinationAmount else {
            // A half that can't tell its partner apart says only that (D330.2); it isn't a lone half.
            if !row.issues.contains(.ambiguousTransferHalf) {
                found.append((.destinationAmountRequired, nil))
            }
            return nil
        }
        if !fits(received, destination) {
            found.append((.tooManyDecimalPlaces(currencyCode: destination), row.columns.destinationAmount))
            return nil
        }
        return received
    }

    /// The column of the row's first reason: from reading when reading found one, otherwise the cell behind
    /// the first reason matching found (D349.1). `nil` when the first reason is about the whole row.
    private static func issueColumn(
        of input: ImportRow,
        found: [(issue: ImportRowIssue, column: Int?)],
        issues: [ImportRowIssue],
    ) -> Int? {
        if let first = input.issues.first {
            return issues.first == first ? input.issueColumn : nil
        }
        guard let first = found.first, issues.first == first.issue else {
            return nil
        }
        return first.column
    }

    /// Extra decimals are fine when they're zeros: `1500.00` in JPY is 1500 (D39.1).
    static func fits(_ amount: Decimal, _ currency: String) -> Bool {
        (try? MinorUnitDecimal.validate(amount, currencyCode: currency)) != nil
    }
}

/// Flags rows that look like transactions already in the app. Rows are only compared with the ledger, never
/// with each other (D28).
struct ImportDuplicateDetector {
    /// ±3 calendar days, both ends included (#30 S11, S13).
    static let windowDays = 3

    private struct Bucket: Hashable {
        var accountID: UUID
        var type: TransactionType
        var amount: Decimal
    }

    private let buckets: [Bucket: [Transaction]]
    private let payeeNames: [UUID: String]
    private let timeZone: TimeZone
    /// The stored zones by ID, made once: creating a `TimeZone` per candidate dominated a 10,000-row check.
    private let zones: [String: TimeZone]

    init(ledger: TransactionLedger, timeZone: TimeZone) {
        var buckets: [Bucket: [Transaction]] = [:]
        var zones: [String: TimeZone] = [:]
        for transaction in ledger.transactions where transaction.deletedAt == nil {
            if zones[transaction.timeZoneID] == nil {
                zones[transaction.timeZoneID] = TimeZone(identifier: transaction.timeZoneID) ?? timeZone
            }
            guard let accountID = transaction.accountID else {
                continue
            }
            let bucket = Bucket(accountID: accountID, type: transaction.type, amount: transaction.amount)
            buckets[bucket, default: []].append(transaction)
        }
        self.buckets = buckets
        payeeNames = Dictionary(ledger.payees.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        self.timeZone = timeZone
        self.zones = zones
    }

    func status(of draft: ImportDraft, row: ImportRow) -> ImportRowStatus {
        guard case .existing(let accountID) = draft.account else {
            return .ready
        }
        let bucket = Bucket(accountID: accountID, type: draft.kind.transactionType, amount: draft.amount)
        let candidates = (buckets[bucket] ?? []).filter { sameCounterpart($0, draft) }
        if let exact = candidates.first(where: { isExact($0, draft, rule: row.exactMatch) }) {
            return .alreadyImported(existingID: exact.id)
        }
        let day = dayNumber(draft.date, timeZoneID: draft.timeZoneID)
        let texts = Self.texts([row.payee, row.details])
        if let close = candidates.first(where: { existing in
            abs(dayNumber(existing.date, timeZoneID: existing.timeZoneID) - day) <= Self.windowDays
                && Self.textsMatch(texts, Self.texts([existing.payeeID.flatMap { payeeNames[$0] }, existing.details]))
        }) {
            return .possibleDuplicate(existingID: close.id)
        }
        return .ready
    }

    /// The other side must agree: the same destination for a transfer, and a refund only matches a refund.
    private func sameCounterpart(_ existing: Transaction, _ draft: ImportDraft) -> Bool {
        if draft.kind == .transfer {
            guard case .existing(let id)? = draft.toAccount else {
                return false
            }
            return existing.transferAccountID == id
        }
        return existing.isRefund == (draft.kind == .refund)
    }

    private func isExact(_ existing: Transaction, _ draft: ImportDraft, rule: ImportExactMatch) -> Bool {
        guard abs(existing.date.timeIntervalSince(draft.date)) < 1 else {
            return false
        }
        let category: UUID? =
            switch draft.category {
            case .existing(let id): id
            case .new: UUID()  // A category the import creates can't be on an existing transaction.
            case nil: nil
            }
        if rule == .categoryAndNotes {
            // #60: the same account, date and time, amount, type, category and notes (D324.2).
            return existing.categoryID == category && LedgerText.trimmedOptional(existing.note) == draft.note
        }
        let payee: String? =
            switch draft.payee {
            case .existing(let id): payeeNames[id]
            case .new(let key): key.nameKey
            case nil: nil
            }
        let existingPayee = existing.payeeID.flatMap { payeeNames[$0] }
        return existing.categoryID == category
            && existingPayee.map(ImportText.nameKey) == payee.map(ImportText.nameKey)
            && LedgerText.trimmedOptional(existing.details) == draft.details
            && LedgerText.trimmedOptional(existing.note) == draft.note
            && existing.destinationAmount == draft.destinationAmount
    }

    /// Lowercased, with runs of spaces collapsed; blanks left out.
    static func texts(_ values: [String?]) -> [String] {
        values.compactMap { value in
            guard let value else { return nil }
            let normalized = value.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return normalized.isEmpty ? nil : normalized
        }
    }

    /// One text matches or contains the other (D18). Two rows with no payee or description at all match too,
    /// so a likely copy is never ticked silently.
    static func textsMatch(_ lhs: [String], _ rhs: [String]) -> Bool {
        if lhs.isEmpty && rhs.isEmpty {
            return true
        }
        return lhs.contains { left in rhs.contains { right in left.contains(right) || right.contains(left) } }
    }

    /// Days since 1970 of the moment's calendar day in its own zone, for the ±3-day window.
    private func dayNumber(_ date: Date, timeZoneID: String) -> Int {
        let zone = zones[timeZoneID] ?? TimeZone(identifier: timeZoneID) ?? timeZone
        let seconds = date.timeIntervalSince1970 + TimeInterval(zone.secondsFromGMT(for: date))
        return Int((seconds / 86_400).rounded(.down))
    }
}

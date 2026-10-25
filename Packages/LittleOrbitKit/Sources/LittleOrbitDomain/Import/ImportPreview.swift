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
        var resolved: [(ImportRow, ImportDraft?)] = []
        resolved.reserveCapacity(rows.count)
        for row in rows {
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

    private static func resolve(
        _ input: ImportRow,
        matcher: inout ImportMatcher,
        target: Account?,
        timeZone: TimeZone,
    ) -> (ImportRow, ImportDraft?) {
        var row = input
        var issues = row.issues
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
                issues.append(.currencyMismatch(accountCurrency: currency))
            }
            if let amount = row.amount, !fits(amount, currency) {
                issues.append(.tooManyDecimalPlaces(currencyCode: currency))
            }
            if let toAccount {
                destination = checkTransfer(row, from: account, to: toAccount, matcher: matcher, issues: &issues)
            }
        }
        row.issues = issues
        guard issues.isEmpty, let kind = row.kind, let date = row.date, let amount = row.amount, let account else {
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
        issues: inout [ImportRowIssue],
    ) -> Decimal? {
        if account == toAccount {
            issues.append(.sameTransferAccount)
            return nil
        }
        let source = matcher.currency(of: account)
        let destination = matcher.currency(of: toAccount)
        if source == destination {
            if let received = row.destinationAmount, received != row.amount {
                issues.append(.destinationAmountMismatch)
            }
            return nil
        }
        guard let received = row.destinationAmount else {
            issues.append(.destinationAmountRequired)
            return nil
        }
        if !fits(received, destination) {
            issues.append(.tooManyDecimalPlaces(currencyCode: destination))
            return nil
        }
        return received
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
        if let exact = candidates.first(where: { isExact($0, draft) }) {
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

    private func isExact(_ existing: Transaction, _ draft: ImportDraft) -> Bool {
        guard abs(existing.date.timeIntervalSince(draft.date)) < 1 else {
            return false
        }
        let category: UUID? =
            switch draft.category {
            case .existing(let id): id
            case .new: UUID()  // A category the import creates can't be on an existing transaction.
            case nil: nil
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

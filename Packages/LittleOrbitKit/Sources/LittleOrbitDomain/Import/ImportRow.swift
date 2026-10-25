import Foundation

/// What a row becomes. A refund is an income in an expense category; imported refunds have no link, so they
/// show as “Refund (original deleted)” (D35.2, D286, D319.1).
public enum ImportRowKind: String, CaseIterable, Sendable, Codable {
    case expense
    case income
    case refund
    case transfer

    public var transactionType: TransactionType {
        switch self {
        case .expense: .expense
        case .income, .refund: .income
        case .transfer: .transfer
        }
    }

    /// The kind of category the row's Category column names.
    public var categoryKind: CategoryKind? {
        switch self {
        case .expense, .refund: .expense
        case .income: .income
        case .transfer: nil
        }
    }
}

/// A category as a file names it: a top-level name, or a subcategory under its parent.
public struct ImportCategoryPath: Equatable, Hashable, Sendable {
    public var parent: String?
    public var name: String

    public init(parent: String? = nil, name: String) {
        self.parent = parent
        self.name = name
    }
}

/// Why a row can't be imported. The screens word each case; rows list their reasons in column order.
public enum ImportRowIssue: Equatable, Hashable, Sendable {
    /// The row has fewer fields than a mapped column needs.
    case missingColumns
    /// The file ended inside this row's quoted field.
    case unclosedQuote
    case missingDate
    case unreadableDate
    case unknownType
    case missingAccount
    /// A transfer with no To Account.
    case missingToAccount
    /// “To Account must differ from Account” (D50, D108).
    case sameTransferAccount
    case missingAmount
    /// “Unrecognised amount” (D38.2).
    case unreadableAmount
    /// “Amount is zero” (D114).
    case zeroAmount
    /// The Expense and Income columns both have an amount.
    case conflictingAmounts
    /// More decimals than the account's currency has, and they aren't zeros (D39.1, #30 S32).
    case tooManyDecimalPlaces(currencyCode: String)
    case unreadableDestinationAmount
    /// “Destination Amount is required when the currencies differ” (D29).
    case destinationAmountRequired
    /// “Destination Amount must equal Amount for same-currency transfers” (D29).
    case destinationAmountMismatch
    case unknownCurrency
    /// The Currency column doesn't match the account's currency. Amounts are never converted.
    case currencyMismatch(accountCurrency: String)
    /// An account, category or payee name over 100 characters.
    case nameTooLong(ImportField)
    /// Two halves of one transfer between accounts in the same currency, with different amounts (D330).
    case transferAmountsMismatch
    /// More than one row is equally close to be this transfer's other half, and they'd make different
    /// transfers (D330).
    case ambiguousTransferHalf
}

extension ImportRowIssue {
    /// The field a reason is about, for formats that list reasons in a fixed field order (D111), or `nil` when
    /// it's about the whole row, which comes first.
    public var field: ImportField? {
        switch self {
        case .missingColumns, .unclosedQuote: nil
        case .missingDate, .unreadableDate, .ambiguousTransferHalf: .date
        case .unknownType: .type
        case .missingAccount: .account
        case .missingToAccount, .sameTransferAccount: .toAccount
        case .missingAmount, .unreadableAmount, .zeroAmount, .conflictingAmounts, .tooManyDecimalPlaces,
            .transferAmountsMismatch:
            .amount
        case .unreadableDestinationAmount, .destinationAmountRequired, .destinationAmountMismatch: .destinationAmount
        case .unknownCurrency, .currencyMismatch: .currency
        case .nameTooLong(let field): field
        }
    }
}

/// Which fields an “Already imported” match compares, besides the account, type, amount and moment.
public enum ImportExactMatch: Equatable, Hashable, Sendable {
    /// #30: the category, payee, description, notes and destination too (D42).
    case everyField
    /// #60: the category and notes too, so payee and description are left out (D324.2).
    case categoryAndNotes
}

/// Something about a row that still imports (D105, D114).
public enum ImportRowWarning: Equatable, Hashable, Sendable {
    /// The description was cut to its first 100 characters (D105).
    case descriptionShortened
    /// The notes were cut to 2,000 characters (D38.6, D114).
    case notesShortened
}

/// Which half of a transfer a file's row is, for a format that lists a transfer once under each of its accounts
/// (#60). The planner pairs the halves once the accounts are matched (D330).
public enum ImportTransferHalf: Equatable, Hashable, Sendable {
    /// The row's amount left its account: a negative amount in Debit & Credit.
    case outgoing
    /// The row's amount came into its account: a positive amount in Debit & Credit.
    case incoming
}

/// One data row read from a file by an `ImportFormat`, before it's matched against the ledger. Every format
/// (generic CSV #30, Debit & Credit #60, bank files #37) produces these, so matching, duplicates, preview and
/// commit are shared.
public struct ImportRow: Equatable, Sendable, Identifiable {
    /// The spreadsheet row number (D43), which also identifies the row.
    public var rowNumber: Int
    public var kind: ImportRowKind?
    public var date: Date?
    /// The amount as a positive magnitude.
    public var amount: Decimal?
    public var destinationAmount: Decimal?
    public var accountName: String?
    public var toAccountName: String?
    public var currencyCode: String?
    public var category: ImportCategoryPath?
    public var payee: String?
    public var details: String?
    public var note: String?
    /// Reasons it can't be imported, found while reading. Matching can add more.
    public var issues: [ImportRowIssue]
    public var warnings: [ImportRowWarning]
    /// Rows this one stands for besides itself, such as the other half of a transfer the planner paired (#60).
    public var mergedRowNumbers: [Int]
    /// For a transfer half the planner should pair with its other half (#60, D330); `nil` for every other row.
    /// `accountName` and `toAccountName` are already in the transfer's direction.
    public var transferHalf: ImportTransferHalf?
    /// A transfer half's Date and Amount columns, so a pairing reason can show the file's value (D323.3, D330).
    public var transferColumns: [ImportField: Int]
    /// The column the first of `issues` is about, so Review can show its header and raw value (D323.3, D349),
    /// or `nil` when that issue is about the whole row.
    public var issueColumn: Int?
    /// The columns the checked values came from, so a reason found after reading can name its cell (D349.1).
    public var columns: ImportRowColumns
    /// When not empty, the fixed order reasons are listed in, including those matching adds (D111). Empty keeps
    /// the order they were found in.
    public var issueOrder: [ImportField]
    /// What an “Already imported” match compares for this row's format.
    public var exactMatch: ImportExactMatch

    public var id: Int {
        rowNumber
    }

    public init(
        rowNumber: Int,
        kind: ImportRowKind? = nil,
        date: Date? = nil,
        amount: Decimal? = nil,
        destinationAmount: Decimal? = nil,
        accountName: String? = nil,
        toAccountName: String? = nil,
        currencyCode: String? = nil,
        category: ImportCategoryPath? = nil,
        payee: String? = nil,
        details: String? = nil,
        note: String? = nil,
        issues: [ImportRowIssue] = [],
        warnings: [ImportRowWarning] = [],
        mergedRowNumbers: [Int] = [],
        transferHalf: ImportTransferHalf? = nil,
        transferColumns: [ImportField: Int] = [:],
        issueColumn: Int? = nil,
        columns: ImportRowColumns = ImportRowColumns(),
        issueOrder: [ImportField] = [],
        exactMatch: ImportExactMatch = .everyField,
    ) {
        self.rowNumber = rowNumber
        self.kind = kind
        self.date = date
        self.amount = amount
        self.destinationAmount = destinationAmount
        self.accountName = accountName
        self.toAccountName = toAccountName
        self.currencyCode = currencyCode
        self.category = category
        self.payee = payee
        self.details = details
        self.note = note
        self.issues = issues
        self.warnings = warnings
        self.mergedRowNumbers = mergedRowNumbers
        self.transferHalf = transferHalf
        self.transferColumns = transferColumns
        self.issueColumn = issueColumn
        self.columns = columns
        self.issueOrder = issueOrder
        self.exactMatch = exactMatch
    }

    /// `issues` in `issueOrder`, reasons about the whole row first; the order found is kept within a field.
    func issuesInFieldOrder(_ issues: [ImportRowIssue]) -> [ImportRowIssue] {
        guard !issueOrder.isEmpty else {
            return issues
        }
        func rank(_ issue: ImportRowIssue) -> Int {
            guard let field = issue.field else {
                return -1
            }
            return issueOrder.firstIndex(of: field) ?? issueOrder.count
        }
        return issues.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }
}

/// Where a row's checked values are in the file: the column each was read from, or `nil` when the format
/// didn't read it from one cell. Matching names these cells under its reasons (D349.1).
public struct ImportRowColumns: Equatable, Sendable {
    /// The column the amount came from: Amount, or the Expense Amount or Income Amount that was filled in.
    public var amount: Int?
    public var destinationAmount: Int?
    public var toAccount: Int?
    public var currency: Int?

    public init(amount: Int? = nil, destinationAmount: Int? = nil, toAccount: Int? = nil, currency: Int? = nil) {
        self.amount = amount
        self.destinationAmount = destinationAmount
        self.toAccount = toAccount
        self.currency = currency
    }
}

/// Shortening shared by every format.
public enum ImportText {
    public static let nameLimit = LedgerText.nameLimit
    public static let noteLimit = LedgerText.noteLimit

    /// Notes over 2,000 characters keep 1,999 whole characters plus “…” (D38.6, D39.4).
    public static func shortenedNote(_ text: String) -> (text: String, wasShortened: Bool) {
        guard text.count > noteLimit else {
            return (text, false)
        }
        return (String(text.prefix(noteLimit - 1)) + "…", true)
    }

    /// A line break inside a quoted cell is one LF, whatever the file's line endings: a CRLF, a CR CR LF or a
    /// lone CR becomes LF, so a file saved on Windows leaves no carriage return in a description or a note.
    /// Read scalar by scalar, since Swift's characters fold CR LF into one and would hide a CR before it.
    public static func lineBreaks(_ text: String) -> String {
        guard text.unicodeScalars.contains("\r") else {
            return text
        }
        return CSVLineBreak.normalized(text)
    }

    /// Trimmed, or `nil` when blank.
    public static func value(_ text: String?) -> String? {
        LedgerText.trimmedOptional(text)
    }

    /// Case- and space-insensitive key for matching names (D38, design rule “by name, ignoring case and extra
    /// spaces”).
    public static func nameKey(_ name: String) -> String {
        LedgerText.nameKey(name.split(whereSeparator: \.isWhitespace).joined(separator: " "))
    }
}

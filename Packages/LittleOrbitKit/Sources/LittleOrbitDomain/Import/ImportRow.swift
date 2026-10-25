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
}

/// Something about a row that still imports (D105, D114).
public enum ImportRowWarning: Equatable, Hashable, Sendable {
    /// The description was cut to its first 100 characters (D105).
    case descriptionShortened
    /// The notes were cut to 2,000 characters (D38.6, D114).
    case notesShortened
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
    /// Rows this one stands for besides itself, such as the other half of a transfer a format paired (#60).
    public var mergedRowNumbers: [Int]
    /// The column the first of `issues` is about, so Review can show its header and raw value (D323.3), or
    /// `nil` when that issue is about the whole row.
    public var issueColumn: Int?

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
        issueColumn: Int? = nil,
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
        self.issueColumn = issueColumn
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

    /// A line break inside a quoted cell is one LF, whatever the file's line endings: a CRLF or a lone CR
    /// becomes LF, so a file saved on Windows leaves no carriage return in a description or a note.
    public static func lineBreaks(_ text: String) -> String {
        guard text.contains(where: \.isNewline) else {
            return text
        }
        return text.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
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

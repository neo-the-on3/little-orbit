import Foundation

/// What a file column holds. Columns mapped to nothing are not imported.
public enum ImportField: String, CaseIterable, Sendable, Codable, Hashable {
    case date
    case type
    case account
    case toAccount
    /// One signed column: negative is an expense, positive an income (or the type column decides).
    case amount
    case destinationAmount
    case currency
    /// The debit/withdrawal column of a two-column file.
    case expenseAmount
    /// The credit/deposit column of a two-column file.
    case incomeAmount
    case category
    case payee
    case description
    case notes
}

/// Which column each field comes from. A field is in at most one column and a column holds at most one field.
public struct ImportColumnMapping: Equatable, Sendable, Codable {
    public private(set) var fieldsByColumn: [Int: ImportField]

    public init(_ fieldsByColumn: [Int: ImportField] = [:]) {
        self.fieldsByColumn = [:]
        for (column, field) in fieldsByColumn.sorted(by: { $0.key < $1.key }) {
            assign(field, to: column)
        }
    }

    public func field(at column: Int) -> ImportField? {
        fieldsByColumn[column]
    }

    public func column(for field: ImportField) -> Int? {
        fieldsByColumn.first { $0.value == field }?.key
    }

    /// Puts `field` in `column`, taking it off any other column; `nil` stops importing the column.
    public mutating func assign(_ field: ImportField?, to column: Int) {
        if let field, let previous = self.column(for: field) {
            fieldsByColumn[previous] = nil
        }
        fieldsByColumn[column] = field
    }

    public var hasAmount: Bool {
        column(for: .amount) != nil || column(for: .expenseAmount) != nil || column(for: .incomeAmount) != nil
    }

    /// The required fields still unmapped: Date, and an amount (one signed Amount column, or Expense and/or
    /// Income columns). Next stays disabled until this is empty (#30 S29).
    public var missingRequired: [ImportField] {
        var missing: [ImportField] = []
        if column(for: .date) == nil {
            missing.append(.date)
        }
        if !hasAmount {
            missing.append(.amount)
        }
        return missing
    }

    /// The mapping a header suggests, by the names banks and apps commonly use. Unknown columns stay unmapped.
    public static func suggested(for header: [String]) -> ImportColumnMapping {
        var mapping = ImportColumnMapping()
        let keys = header.map(normalizedName)
        for (field, names) in synonyms where mapping.column(for: field) == nil {
            if let column = keys.indices.first(where: { names.contains(keys[$0]) && mapping.field(at: $0) == nil }) {
                mapping.assign(field, to: column)
            }
        }
        return mapping
    }

    /// Lowercased, with punctuation dropped and spaces collapsed: "Withdrawal Amt." → "withdrawal amt".
    public static func normalizedName(_ name: String) -> String {
        let kept = name.lowercased().unicodeScalars
            .map { scalar -> Character in
                CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
            }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// In priority order: an exact app-export name is tried before looser bank names.
    private static let synonyms: [(ImportField, Set<String>)] = [
        (.date, ["date", "transaction date", "txn date", "posting date", "booking date", "value date", "tran date"]),
        (.type, ["type", "transaction type"]),
        (.account, ["account", "account name", "from account"]),
        (.toAccount, ["to account", "transfer account", "destination account"]),
        (.destinationAmount, ["destination amount", "received amount"]),
        (.amount, ["amount", "transaction amount", "amt"]),
        (.currency, ["currency", "currency code"]),
        (
            .expenseAmount,
            [
                "debit", "debits", "withdrawal", "withdrawals", "withdrawal amt", "withdrawal amount", "expense",
                "expense amount", "money out", "paid out", "debit amount", "dr",
            ],
        ),
        (
            .incomeAmount,
            [
                "credit", "credits", "deposit", "deposits", "deposit amt", "deposit amount", "income", "income amount",
                "money in", "paid in", "credit amount", "cr",
            ],
        ),
        (.category, ["category"]),
        (.payee, ["payee", "merchant", "counterparty", "payee name"]),
        (
            .description,
            ["description", "narration", "particulars", "details", "transaction details", "transaction description"],
        ),
        (.notes, ["notes", "note", "memo", "remarks", "comment", "comments"]),
    ]
}

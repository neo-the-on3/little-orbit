import Foundation

/// How a file's rows are read: which column holds what, the date order and the decimal separator, and the
/// time zone the dates are wall times in.
public struct ImportReadSettings: Equatable, Sendable {
    public var mapping: ImportColumnMapping
    public var dateOrder: ImportDateOrder
    public var decimalSeparator: ImportDecimalSeparator
    public var timeZone: TimeZone

    public init(
        mapping: ImportColumnMapping,
        dateOrder: ImportDateOrder,
        decimalSeparator: ImportDecimalSeparator,
        timeZone: TimeZone,
    ) {
        self.mapping = mapping
        self.dateOrder = dateOrder
        self.decimalSeparator = decimalSeparator
        self.timeZone = timeZone
    }
}

/// A source format: the pluggable stage of the import pipeline.
///
/// The pipeline is read → map columns → rows → match and preview → commit. Only the first steps differ by
/// source, so a format decides whether a header is its own, what mapping to start from and how a record becomes
/// an `ImportRow`. Matching, duplicates, the preview, commit and Undo Import are shared. The generic CSV format
/// is #30's; #60's Debit & Credit preset plugs in as another `ImportFormat` in `ImportFormats`, with its own
/// category splitting, notes joining and transfer pairing in `rows(from:settings:)`.
public protocol ImportFormat: Sendable {
    /// A stable identifier, such as `generic` or `debitAndCredit`.
    var id: String { get }
    /// Whether the header is this format's, so it's applied without asking (D44). The generic format never
    /// claims a header; it's the fallback.
    func recognises(header: [String]) -> Bool
    /// The mapping the Columns step starts from. It stays editable.
    func suggestedMapping(for header: [String]) -> ImportColumnMapping
    /// The data records as rows, with reasons in the format's column order (D111).
    func rows(from table: CSVTable, settings: ImportReadSettings) -> [ImportRow]
}

/// The formats an import can use, specific ones first. The first that recognises a header is applied;
/// otherwise the generic CSV format is.
public struct ImportFormats: Sendable {
    public var specific: [any ImportFormat]
    public var generic: any ImportFormat

    public init(specific: [any ImportFormat] = [], generic: any ImportFormat = GenericCSVFormat()) {
        self.specific = specific
        self.generic = generic
    }

    public func format(for header: [String]) -> any ImportFormat {
        specific.first { $0.recognises(header: header) } ?? generic
    }

    public func format(id: String) -> any ImportFormat {
        specific.first { $0.id == id } ?? generic
    }
}

/// #30's generic CSV: any columns, mapped by the user from a suggestion.
///
/// Amounts come from one signed Amount column (negative is an expense) or from Expense and Income columns.
/// An optional Type column says Expense, Income, Transfer or Refund (also Debit, Credit, DR and CR), and then
/// decides the kind whatever the sign. A transfer is one row with Account, To Account, Amount sent and an
/// optional Destination Amount received (D25, D41). A category is a name or `Parent › Child`, the way the
/// export writes it.
public struct GenericCSVFormat: ImportFormat {
    public static let categorySeparator = " › "

    public init() {}

    public var id: String {
        "generic"
    }

    public func recognises(header: [String]) -> Bool {
        false
    }

    public func suggestedMapping(for header: [String]) -> ImportColumnMapping {
        .suggested(for: header)
    }

    public func rows(from table: CSVTable, settings: ImportReadSettings) -> [ImportRow] {
        table.records.map { row(from: $0, settings: settings) }
    }

    func row(from record: CSVRecord, settings: ImportReadSettings) -> ImportRow {
        var reader = RowReader(record: record, mapping: settings.mapping)
        var row = ImportRow(rowNumber: record.rowNumber)
        if record.isUnterminated {
            reader.fail(.unclosedQuote, at: -1)
        }
        if let highest = settings.mapping.fieldsByColumn.keys.max(), highest >= record.fields.count,
            !record.isUnterminated
        {
            reader.fail(.missingColumns, at: -1)
        }
        readDate(&row, &reader, settings)
        let typed = readType(&reader)
        readAmounts(&row, &reader, typed: typed, settings: settings)
        readNames(&row, &reader)
        readTexts(&row, &reader)
        if row.kind == .transfer {
            row.category = nil
            row.payee = nil
            if row.toAccountName == nil {
                reader.fail(.missingToAccount, at: reader.column(.toAccount) ?? reader.column(.type) ?? Int.max)
            }
        } else {
            row.toAccountName = nil
            row.destinationAmount = nil
        }
        row.issues = reader.orderedIssues
        row.issueColumn = reader.firstIssueColumn
        return row
    }

    private func readDate(_ row: inout ImportRow, _ reader: inout RowReader, _ settings: ImportReadSettings) {
        guard let text = reader.value(.date) else {
            reader.fail(.missingDate, at: reader.column(.date) ?? -1)
            return
        }
        guard let wallTime = ImportDateParser.wallTime(text, order: settings.dateOrder) else {
            reader.fail(.unreadableDate, at: reader.column(.date) ?? -1)
            return
        }
        row.date = ImportDateParser.date(wallTime, in: settings.timeZone)
    }

    /// The Type column's kind, `nil` when there's no column or it's blank.
    private func readType(_ reader: inout RowReader) -> ImportRowKind? {
        guard let text = reader.value(.type) else {
            return nil
        }
        switch ImportColumnMapping.normalizedName(text) {
        case "expense", "debit", "dr", "withdrawal", "payment": return .expense
        case "income", "credit", "cr", "deposit": return .income
        case "transfer": return .transfer
        case "refund": return .refund
        default:
            reader.fail(.unknownType, at: reader.column(.type) ?? -1)
            return nil
        }
    }

    private func readAmounts(
        _ row: inout ImportRow,
        _ reader: inout RowReader,
        typed: ImportRowKind?,
        settings: ImportReadSettings,
    ) {
        let separator = settings.decimalSeparator
        var signed: Decimal?
        var amountColumn = reader.column(.amount) ?? reader.column(.expenseAmount) ?? -1
        if let text = reader.value(.amount) {
            guard let value = ImportAmountParser.parse(text, decimalSeparator: separator) else {
                reader.fail(.unreadableAmount, at: amountColumn)
                return
            }
            signed = value
        } else if reader.column(.expenseAmount) != nil || reader.column(.incomeAmount) != nil {
            guard let pair = twoColumnAmount(&reader, separator: separator, column: amountColumn) else {
                return
            }
            (signed, amountColumn) = (pair.signed, pair.column)
        } else {
            reader.fail(.missingAmount, at: amountColumn)
            return
        }
        guard let signed else {
            reader.fail(.missingAmount, at: amountColumn)
            return
        }
        if signed == 0 {
            reader.fail(.zeroAmount, at: amountColumn)
            return
        }
        row.amount = signed.magnitude
        row.kind = typed ?? (signed < 0 ? .expense : .income)
        if let text = reader.value(.destinationAmount) {
            if let value = ImportAmountParser.parse(text, decimalSeparator: separator), value != 0 {
                row.destinationAmount = value.magnitude
            } else {
                reader.fail(.unreadableDestinationAmount, at: reader.column(.destinationAmount)!)
            }
        }
    }

    /// The signed amount from debit and credit columns, and the column it came from, or `nil` after recording
    /// why there's none.
    private func twoColumnAmount(
        _ reader: inout RowReader,
        separator: ImportDecimalSeparator,
        column: Int,
    ) -> (signed: Decimal, column: Int)? {
        let expenseColumn = reader.column(.expenseAmount) ?? column
        let incomeColumn = reader.column(.incomeAmount) ?? column
        let expense = reader.value(.expenseAmount)
        let income = reader.value(.incomeAmount)
        let expenseValue = expense.flatMap { ImportAmountParser.parse($0, decimalSeparator: separator) }
        let incomeValue = income.flatMap { ImportAmountParser.parse($0, decimalSeparator: separator) }
        if expense != nil && expenseValue == nil {
            reader.fail(.unreadableAmount, at: expenseColumn)
            return nil
        }
        if income != nil && incomeValue == nil {
            reader.fail(.unreadableAmount, at: incomeColumn)
            return nil
        }
        let paid = expenseValue.map(\.magnitude).flatMap { $0 == 0 ? nil : $0 }
        let received = incomeValue.map(\.magnitude).flatMap { $0 == 0 ? nil : $0 }
        switch (paid, received) {
        case (let paid?, nil):
            return (-paid, column)
        case (nil, let received?):
            return (received, incomeColumn)
        case (.some, .some):
            reader.fail(.conflictingAmounts, at: column)
        case (nil, nil):
            let zero = expenseValue != nil || incomeValue != nil
            reader.fail(zero ? .zeroAmount : .missingAmount, at: column)
        }
        return nil
    }

    private func readNames(_ row: inout ImportRow, _ reader: inout RowReader) {
        row.accountName = reader.name(.account)
        row.toAccountName = reader.name(.toAccount)
        row.payee = reader.name(.payee)
        if let code = reader.value(.currency) {
            let normalized = CurrencyCode.normalize(code)
            if CurrencyCode.minorUnits(for: normalized) == nil {
                reader.fail(.unknownCurrency, at: reader.column(.currency)!)
            } else {
                row.currencyCode = normalized
            }
        }
        if let text = reader.value(.category) {
            let path: ImportCategoryPath
            if let range = text.range(of: Self.categorySeparator, options: .backwards) {
                let parent = ImportText.value(String(text[..<range.lowerBound]))
                let name = ImportText.value(String(text[range.upperBound...]))
                switch (parent, name) {
                case (let parent?, let name?): path = ImportCategoryPath(parent: parent, name: name)
                case (let only?, nil), (nil, let only?): path = ImportCategoryPath(name: only)
                case (nil, nil): return
                }
            } else {
                path = ImportCategoryPath(name: text)
            }
            if path.name.count > ImportText.nameLimit || (path.parent?.count ?? 0) > ImportText.nameLimit {
                reader.fail(.nameTooLong(.category), at: reader.column(.category)!)
            } else {
                row.category = path
            }
        }
    }

    private func readTexts(_ row: inout ImportRow, _ reader: inout RowReader) {
        if let details = reader.value(.description) {
            let shortened = DescriptionLimit.shortenedForImport(details)
            row.details = shortened.text
            if shortened.wasShortened {
                row.warnings.append(.descriptionShortened)
            }
        }
        if let note = reader.value(.notes) {
            let shortened = ImportText.shortenedNote(note)
            row.note = shortened.text
            if shortened.wasShortened {
                row.warnings.append(.notesShortened)
            }
        }
    }
}

/// Reads one record's mapped fields and collects its reasons with the column each belongs to.
struct RowReader {
    let record: CSVRecord
    let mapping: ImportColumnMapping
    private var issues: [(column: Int, issue: ImportRowIssue)] = []

    init(record: CSVRecord, mapping: ImportColumnMapping) {
        self.record = record
        self.mapping = mapping
    }

    func column(_ field: ImportField) -> Int? {
        mapping.column(for: field)
    }

    /// The field's trimmed text, or `nil` when it's unmapped, missing or blank.
    func value(_ field: ImportField) -> String? {
        guard let column = mapping.column(for: field) else {
            return nil
        }
        return ImportText.value(record.field(column))
    }

    /// A name field, or `nil` with a reason when it's over the 100-character limit.
    mutating func name(_ field: ImportField) -> String? {
        guard let text = value(field) else {
            return nil
        }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if collapsed.count > ImportText.nameLimit {
            fail(.nameTooLong(field), at: column(field) ?? Int.max)
            return nil
        }
        return collapsed
    }

    mutating func fail(_ issue: ImportRowIssue, at column: Int) {
        guard !issues.contains(where: { $0.issue == issue }) else {
            return
        }
        issues.append((column, issue))
    }

    /// The reasons in column order; reasons about the whole row first.
    var orderedIssues: [ImportRowIssue] {
        ordered.map(\.issue)
    }

    /// The column of the first reason, or `nil` when it's about the whole row or no column is mapped for it.
    var firstIssueColumn: Int? {
        guard let column = ordered.first?.column, column >= 0, column < record.fields.count else {
            return nil
        }
        return column
    }

    private var ordered: [(column: Int, issue: ImportRowIssue)] {
        issues.enumerated()
            .sorted { ($0.element.column, $0.offset) < ($1.element.column, $1.offset) }
            .map(\.element)
    }
}

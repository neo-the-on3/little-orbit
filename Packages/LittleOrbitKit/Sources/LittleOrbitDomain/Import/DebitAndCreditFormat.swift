import Foundation

/// The CSV that Debit & Credit exports (#60, D36).
///
/// Its header is `"Date","Description","Category","Payee","Notes","Account","Transfer Account","Amount"`, in
/// any order and case, with or without a byte order mark; extra columns are ignored (D38.1, D44). Dates are
/// `YYYY-MM-DD HH:mm:ss` wall times in the device zone. Amounts are signed with `.` decimals and Western or
/// Indian comma grouping (D38.2, D39.1, D39.2). A category is `Sub - Parent`, split on the last ` - `
/// (D38.4). Description and Notes are joined into the notes (D38.6). A row with a Transfer Account is a
/// transfer half; the planner pairs the two halves of one transfer once the accounts are matched (D38.5, D330).
public struct DebitAndCreditFormat: ImportFormat {
    public static let formatID = "debitAndCredit"

    /// The eight columns in their fixed order, which is also the order row reasons are listed in (D111).
    public static let columns: [(header: String, field: ImportField)] = [
        ("Date", .date),
        ("Description", .description),
        ("Category", .category),
        ("Payee", .payee),
        ("Notes", .notes),
        ("Account", .account),
        ("Transfer Account", .toAccount),
        ("Amount", .amount),
    ]

    /// The fields the format reads; any other field mapped by hand is ignored.
    public static let fields: [ImportField] = columns.map(\.field)

    static let categorySeparator = " - "

    public init() {}

    public var id: String {
        Self.formatID
    }

    /// All eight names, trimmed and ignoring case, in any order (D44).
    public func recognises(header: [String]) -> Bool {
        let names = Set(header.map(Self.key))
        return Self.columns.allSatisfy { names.contains(Self.key($0.header)) }
    }

    /// The eight columns pre-filled; extra columns stay unmapped (“Don’t Import”, D38.1).
    public func suggestedMapping(for header: [String]) -> ImportColumnMapping {
        var mapping = ImportColumnMapping()
        let keys = header.map(Self.key)
        for (name, field) in Self.columns {
            if let column = keys.firstIndex(of: Self.key(name)) {
                mapping.assign(field, to: column)
            }
        }
        return mapping
    }

    public func rows(from table: CSVTable, settings: ImportReadSettings) -> [ImportRow] {
        table.records.map { row(from: $0, settings: settings) }
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: One row

    /// The row. A transfer is put in its direction and marked as the outgoing or incoming half, which the
    /// planner pairs (D330).
    func row(from record: CSVRecord, settings: ImportReadSettings) -> ImportRow {
        var reader = RowReader(record: record, mapping: settings.mapping)
        var row = ImportRow(
            rowNumber: record.rowNumber,
            issueOrder: Self.fields,
            exactMatch: .categoryAndNotes,
        )
        if record.isUnterminated {
            reader.fail(.unclosedQuote, at: -1)
        } else if let highest = settings.mapping.fieldsByColumn.keys.max(), highest >= record.fields.count {
            reader.fail(.missingColumns, at: -1)
        }
        readDate(&row, &reader, settings)
        row.category = readCategory(&reader)
        row.payee = reader.name(.payee)
        readNotes(&row, reader)
        let account = reader.name(.account)
        let transferAccount = reader.name(.toAccount)
        // With no Account column, the chosen target account is used; a transfer still needs both sides.
        if account == nil && (reader.column(.account) != nil || transferAccount != nil) {
            reader.fail(.missingAccount, at: column(.account, reader))
        }
        let signed = readAmount(&reader)
        if let transferAccount {
            // A positive amount moved money from the Transfer Account into the Account.
            row.kind = .transfer
            let incoming = (signed ?? 0) > 0
            row.transferHalf = incoming ? .incoming : .outgoing
            for field in [ImportField.date, .amount] {
                row.transferColumns[field] = reader.column(field)
            }
            row.accountName = incoming ? transferAccount : account
            row.toAccountName = incoming ? account : transferAccount
            row.category = nil
            row.payee = nil
        } else {
            row.accountName = account
            if let signed {
                row.kind = signed < 0 ? .expense : .income
            }
        }
        if let signed {
            row.amount = signed.magnitude
        }
        row.issues = row.issuesInFieldOrder(reader.orderedIssues)
        row.issueColumn = row.issues.first?.field.flatMap(reader.column)
        return row
    }

    private func column(_ field: ImportField, _ reader: RowReader) -> Int {
        reader.column(field) ?? Int.max
    }

    /// `YYYY-MM-DD HH:mm:ss` only: a date alone or another layout isn't read.
    private func readDate(_ row: inout ImportRow, _ reader: inout RowReader, _ settings: ImportReadSettings) {
        guard let text = reader.value(.date) else {
            reader.fail(.missingDate, at: column(.date, reader))
            return
        }
        guard let wallTime = Self.wallTime(text) else {
            reader.fail(.unreadableDate, at: column(.date, reader))
            return
        }
        row.date = ImportDateParser.date(wallTime, in: settings.timeZone)
    }

    public static func wallTime(_ text: String) -> ImportWallTime? {
        let characters = Array(text)
        guard characters.count == 19 else {
            return nil
        }
        let marks: [Int: Character] = [4: "-", 7: "-", 10: " ", 13: ":", 16: ":"]
        for (index, character) in characters.enumerated() {
            if let mark = marks[index] {
                guard character == mark else { return nil }
            } else if !character.isASCIIDigit {
                return nil
            }
        }
        return ImportDateParser.wallTime(text, order: .yearMonthDay)
    }

    /// The signed amount, or `nil` after recording why there's none. Zero is a reason too (D114).
    private func readAmount(_ reader: inout RowReader) -> Decimal? {
        let amountColumn = column(.amount, reader)
        guard let text = reader.value(.amount) else {
            reader.fail(.missingAmount, at: amountColumn)
            return nil
        }
        guard let value = Self.amount(text) else {
            reader.fail(.unreadableAmount, at: amountColumn)
            return nil
        }
        guard value != 0 else {
            reader.fail(.zeroAmount, at: amountColumn)
            return nil
        }
        return value
    }

    /// An optional `-` or `+`, digits with no grouping or valid Western or Indian comma grouping, and
    /// optional `.` decimals (D38.2, D39.2). Decimal commas, parentheses, currency symbols and other text
    /// aren't read. Whether the decimals fit the account's currency is checked once it's matched (D39.1).
    public static func amount(_ text: String) -> Decimal? {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var negative = false
        if let first = body.first, first == "-" || first == "+" {
            negative = first == "-"
            body = body.dropFirst()
        }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else {
            return nil
        }
        let fraction = parts.count == 2 ? parts[1] : ""
        guard parts.count == 1 || !fraction.isEmpty, fraction.allSatisfy(\.isASCIIDigit),
            let digits = integerDigits(parts[0])
        else {
            return nil
        }
        let plain = digits + (fraction.isEmpty ? "" : "." + fraction)
        guard let magnitude = Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return negative ? -magnitude : magnitude
    }

    /// The digits of the integer part once valid comma grouping is taken out, or `nil`.
    private static func integerDigits(_ integer: Substring) -> String? {
        guard !integer.isEmpty else {
            return nil
        }
        if integer.allSatisfy(\.isASCIIDigit) {
            return String(integer)
        }
        let groups = integer.split(separator: ",", omittingEmptySubsequences: false)
        guard groups.count >= 2, groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else {
            return nil
        }
        let first = groups[0]
        let middle = groups.dropFirst().dropLast()
        let last = groups[groups.count - 1]
        let western = (1...3).contains(first.count) && middle.allSatisfy { $0.count == 3 } && last.count == 3
        let indian = (1...2).contains(first.count) && middle.allSatisfy { $0.count == 2 } && last.count == 3
        return western || indian ? groups.joined() : nil
    }

    /// `Sub - Parent` split on the last ` - `, each side trimmed. An empty side leaves a flat category, and
    /// nothing at all is Uncategorised (D38.4). Without spaces on both sides a hyphen is part of the name.
    private func readCategory(_ reader: inout RowReader) -> ImportCategoryPath? {
        guard let text = reader.value(.category) else {
            return nil
        }
        let path: ImportCategoryPath
        // Padding finds a separator at either end of the trimmed value: “ - Food” and “Coffee - ”.
        let padded = " " + text + " "
        if let range = padded.range(of: Self.categorySeparator, options: .backwards) {
            let child = ImportText.value(String(padded[..<range.lowerBound]))
            let parent = ImportText.value(String(padded[range.upperBound...]))
            switch (parent, child) {
            case (let parent?, let child?): path = ImportCategoryPath(parent: parent, name: child)
            case (let only?, nil), (nil, let only?): path = ImportCategoryPath(name: only)
            case (nil, nil): return nil
            }
        } else {
            path = ImportCategoryPath(name: text)
        }
        if path.name.count > ImportText.nameLimit || (path.parent?.count ?? 0) > ImportText.nameLimit {
            reader.fail(.nameTooLong(.category), at: column(.category, reader))
            return nil
        }
        return path
    }

    /// Description on the first line and Notes after it; the same text once; over 2,000 characters
    /// shortened with a warning (D38.6, D39.4).
    private func readNotes(_ row: inout ImportRow, _ reader: RowReader) {
        let description = reader.value(.description)
        let notes = reader.value(.notes)
        let joined: String? =
            switch (description, notes) {
            case (let description?, let notes?): description == notes ? description : description + "\n" + notes
            case (let only?, nil), (nil, let only?): only
            case (nil, nil): nil
            }
        guard let joined else {
            return
        }
        let shortened = ImportText.shortenedNote(joined)
        row.note = shortened.text
        if shortened.wasShortened {
            row.warnings.append(.notesShortened)
        }
    }
}

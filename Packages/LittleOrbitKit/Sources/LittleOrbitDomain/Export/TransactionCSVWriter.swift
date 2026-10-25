import Foundation

/// The records a transaction refers to, by id, for writing it out.
public struct TransactionCSVLookup: Sendable {
    public var accounts: [UUID: Account]
    public var categories: [UUID: TransactionCategory]
    public var payees: [UUID: Payee]

    public init(accounts: [Account], categories: [TransactionCategory], payees: [Payee]) {
        self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.categories = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.payees = Dictionary(payees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public init(_ ledger: TransactionLedger) {
        self.init(accounts: ledger.accounts, categories: ledger.categories, payees: ledger.payees)
    }
}

/// How dates are written.
public enum TransactionCSVDateStyle: Equatable, Sendable {
    /// `2026-10-20 00:00:00` in the transaction's own time zone (#30 AC 5, S37).
    case iso8601
    /// The locale's short date (`20/10/26` on en_IN), in the transaction's own time zone (PM answer 4).
    case shortDate(Locale)
}

/// Writes transactions as the app's CSV (D41, D25, PM answer 4), for any set of transactions: Export
/// Transactions to CSV uses it for everything or a date range, and Search (#187) can pass a result set.
///
/// Columns: `Date, Type, Account, To Account, Amount, Destination Amount, Currency, Category, Payee,
/// Description, Notes`. A transfer is one row with Account as the from-account, Amount sent and Destination
/// Amount received (blank when both accounts share a currency). Amounts use `.` with no grouping and the
/// currency's decimals; expenses are negative. A refund keeps its expense category and has Type `Refund`.
/// A subcategory is written `Parent › Child`. The text is UTF-8 with a byte order mark, comma-separated, CRLF,
/// RFC 4180 quoting, which `GenericCSVFormat` reads back.
///
/// Free-text cells (account names, category, payee, description and notes) that start with `=`, `+`, `-`, `@`,
/// a tab or a carriage return get one leading apostrophe, so a spreadsheet shows them as text instead of running
/// them as a formula (D323.1). Date, Type, amount and currency cells are never prefixed, so a negative amount
/// stays the number `-500.00`. `GenericCSVFormat` removes that apostrophe again on import.
public enum TransactionCSVWriter {
    public static let header = [
        "Date", "Type", "Account", "To Account", "Amount", "Destination Amount", "Currency", "Category", "Payee",
        "Description", "Notes",
    ]

    /// The first characters that make a spreadsheet read a cell as a formula (D323.1).
    public static let formulaTriggers: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]

    /// A free-text cell made safe to open in a spreadsheet: one leading apostrophe when it starts with a formula
    /// trigger (D323.1). Only text goes through this; numbers and dates are never prefixed.
    public static func protectedText(_ text: String) -> String {
        guard let first = text.unicodeScalars.first, formulaTriggers.contains(first) else {
            return text
        }
        return "'" + text
    }

    /// The reverse, for import: one leading apostrophe before a formula trigger is removed, so the app's own
    /// exports read back unchanged (D323.1). Any other leading apostrophe is kept.
    public static func unprotectedText(_ text: String) -> String {
        var scalars = text.unicodeScalars.makeIterator()
        guard scalars.next() == "'", let second = scalars.next(), formulaTriggers.contains(second) else {
            return text
        }
        return String(text.unicodeScalars.dropFirst())
    }

    /// The header and one record per transaction, in the order given.
    public static func records(
        for transactions: [Transaction],
        lookup: TransactionCSVLookup,
        dateStyle: TransactionCSVDateStyle,
    ) -> [[String]] {
        var formatters: [String: DateFormatter] = [:]
        func formatter(_ zoneID: String) -> DateFormatter {
            if let made = formatters[zoneID] {
                return made
            }
            let made = DateFormatter()
            made.calendar = Calendar(identifier: .gregorian)
            made.timeZone = TransactionCalendar.storedTimeZone(zoneID)
            switch dateStyle {
            case .iso8601:
                made.locale = Locale(identifier: "en_US_POSIX")
                made.dateFormat = "yyyy-MM-dd HH:mm:ss"
            case .shortDate(let locale):
                made.locale = locale
                made.dateStyle = .short
                made.timeStyle = .none
            }
            formatters[zoneID] = made
            return made
        }
        var records = [header]
        records.reserveCapacity(transactions.count + 1)
        for transaction in transactions {
            records.append(record(for: transaction, lookup: lookup, date: formatter(transaction.timeZoneID)))
        }
        return records
    }

    /// The CSV text, without a byte order mark.
    public static func text(
        for transactions: [Transaction],
        lookup: TransactionCSVLookup,
        dateStyle: TransactionCSVDateStyle,
    ) -> String {
        CSVWriter.text(records(for: transactions, lookup: lookup, dateStyle: dateStyle))
    }

    /// The file's bytes: UTF-8 with a byte order mark.
    public static func data(
        for transactions: [Transaction],
        lookup: TransactionCSVLookup,
        dateStyle: TransactionCSVDateStyle,
    ) -> Data {
        CSVWriter.data(records(for: transactions, lookup: lookup, dateStyle: dateStyle))
    }

    /// The Type column's value. These are file values, read back by `GenericCSVFormat`, not screen text.
    public static func typeValue(of transaction: Transaction) -> String {
        switch transaction.type {
        case .expense: "Expense"
        case .income: transaction.isRefund ? "Refund" : "Income"
        case .transfer: "Transfer"
        }
    }

    /// `amount` with exactly the currency's decimals, `.` and no grouping: `-125000.50`, `-1500`, `12.345`.
    public static func amountText(_ amount: Decimal, currencyCode: String) -> String {
        let scale = CurrencyCode.minorUnits(for: currencyCode) ?? 2
        var source = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, scale, .plain)
        let negative = rounded < 0
        let plain = NSDecimalNumber(decimal: rounded.magnitude)
            .description(withLocale: Locale(identifier: "en_US_POSIX"))
        var parts = plain.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1 {
            parts.append("")
        }
        let fraction = String((parts[1] + String(repeating: "0", count: scale)).prefix(scale))
        let body = scale == 0 ? parts[0] : parts[0] + "." + fraction
        return negative ? "-" + body : body
    }

    private static func record(
        for transaction: Transaction,
        lookup: TransactionCSVLookup,
        date: DateFormatter,
    ) -> [String] {
        let account = transaction.accountID.flatMap { lookup.accounts[$0] }
        let destination = transaction.transferAccountID.flatMap { lookup.accounts[$0] }
        let currency = account?.currencyCode ?? ""
        let signed = transaction.type == .expense ? -transaction.amount : transaction.amount
        var received = ""
        if transaction.type == .transfer, let destination, destination.currencyCode != currency {
            received = amountText(
                transaction.destinationAmount ?? transaction.amount,
                currencyCode: destination.currencyCode,
            )
        }
        return [
            date.string(from: transaction.date),
            typeValue(of: transaction),
            protectedText(account?.name ?? ""),
            protectedText(transaction.type == .transfer ? destination?.name ?? "" : ""),
            amountText(signed, currencyCode: currency),
            received,
            currency,
            protectedText(categoryText(transaction.categoryID, lookup: lookup)),
            protectedText(transaction.payeeID.flatMap { lookup.payees[$0]?.name } ?? ""),
            protectedText(transaction.details ?? ""),
            protectedText(transaction.note ?? ""),
        ]
    }

    private static func categoryText(_ id: UUID?, lookup: TransactionCSVLookup) -> String {
        guard let category = id.flatMap({ lookup.categories[$0] }) else {
            return ""
        }
        if let parent = category.parentID.flatMap({ lookup.categories[$0] }) {
            return parent.name + GenericCSVFormat.categorySeparator + category.name
        }
        return category.name
    }
}

import Foundation
import LittleOrbitDomain

/// Made-up ledger and file text for the import and export tests.
enum ImportFixture {
    static let zone = "Asia/Kolkata"
    static let india = Locale(identifier: "en_IN")
    static let savingsID = UUID()
    static let walletID = UUID()
    static let travelID = UUID()
    static let foodID = UUID()
    static let groceriesID = UUID()
    static let salaryID = UUID()
    static let cornerShopID = UUID()

    static func timeZone() -> TimeZone {
        TimeZone(identifier: zone) ?? .gmt
    }

    static func accounts() -> [Account] {
        [
            Account(id: savingsID, name: "Everyday Savings", type: .savings, currencyCode: "INR", sortOrder: 1),
            Account(id: walletID, name: "Corner Wallet", type: .cash, currencyCode: "INR", sortOrder: 2),
            Account(id: travelID, name: "Travel Euros", type: .cash, currencyCode: "EUR", sortOrder: 3),
        ]
    }

    static func categories() -> [TransactionCategory] {
        [
            TransactionCategory(id: foodID, name: "Food", kind: .expense, sortOrder: 1),
            TransactionCategory(id: groceriesID, name: "Groceries", kind: .expense, parentID: foodID, sortOrder: 1),
            TransactionCategory(id: salaryID, name: "Salary", kind: .income, sortOrder: 1),
        ]
    }

    static func payees() -> [Payee] {
        [Payee(id: cornerShopID, name: "Corner Shop")]
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        ImportDateParser.date(ImportWallTime(year: year, month: month, day: day, hour: hour), in: timeZone())
    }

    static func ledger(_ transactions: [Transaction] = []) -> TransactionLedger {
        TransactionLedger(accounts: accounts(), transactions: transactions, categories: categories(), payees: payees())
    }

    static func settings(
        _ header: [String],
        order: ImportDateOrder = .yearMonthDay,
        separator: ImportDecimalSeparator = .period,
    ) -> ImportReadSettings {
        ImportReadSettings(
            mapping: ImportColumnMapping.suggested(for: header),
            dateOrder: order,
            decimalSeparator: separator,
            timeZone: timeZone(),
        )
    }

    static func rows(_ text: String, order: ImportDateOrder = .yearMonthDay) throws -> [ImportRow] {
        let table = try CSVReader.read(text)
        return GenericCSVFormat().rows(from: table, settings: settings(table.header, order: order))
    }

    static func preview(
        _ text: String,
        ledger: TransactionLedger = ledger(),
        choices: ImportChoices = ImportChoices(),
    ) throws -> ImportPreview {
        ImportPlanner.preview(
            rows: try rows(text),
            ledger: ledger,
            choices: choices,
            timeZone: timeZone(),
            defaultCurrency: "INR",
        )
    }

    static func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }
}

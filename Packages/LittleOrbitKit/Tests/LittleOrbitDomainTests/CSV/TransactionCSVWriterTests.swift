import Foundation
import LittleOrbitDomain
import Testing

/// The reusable writer (#30 export, #187 search export) and the export use case (D41, PM answer 4).
@Suite("Transaction CSV writer (#30)")
@MainActor
struct TransactionCSVWriterTests {
    typealias F = ImportFixture  // swiftlint:disable:this type_name

    private func transactions() -> [Transaction] {
        [
            Transaction(
                type: .expense,
                amount: F.dec("125000.5"),
                date: F.date(2026, 10, 20, 9),
                timeZoneID: F.zone,
                accountID: F.savingsID,
                categoryID: F.groceriesID,
                payeeID: F.cornerShopID,
                details: "Milk, eggs",
                note: "Line one\nline two",
            ),
            Transaction(
                type: .income,
                amount: 120,
                date: F.date(2026, 10, 21),
                timeZoneID: F.zone,
                accountID: F.savingsID,
                categoryID: F.foodID,
                isRefund: true,
            ),
            Transaction(
                type: .transfer,
                amount: 1000,
                date: F.date(2026, 10, 22),
                timeZoneID: F.zone,
                accountID: F.savingsID,
                transferAccountID: F.travelID,
                destinationAmount: F.dec("10.5"),
            ),
            Transaction(
                type: .transfer,
                amount: 50,
                date: F.date(2026, 10, 23),
                timeZoneID: F.zone,
                accountID: F.savingsID,
                transferAccountID: F.walletID,
            ),
        ]
    }

    private var lookup: TransactionCSVLookup {
        TransactionCSVLookup(accounts: F.accounts(), categories: F.categories(), payees: F.payees())
    }

    @Test("D41 columns, signed amounts with the currency's decimals, Parent › Child categories")
    func records() {
        let records = TransactionCSVWriter.records(for: transactions(), lookup: lookup, dateStyle: .iso8601)
        #expect(records[0] == TransactionCSVWriter.header)
        #expect(
            records[1] == [
                "2026-10-20 09:00:00", "Expense", "Everyday Savings", "", "-125000.50", "", "INR", "Food › Groceries",
                "Corner Shop", "Milk, eggs", "Line one\nline two",
            ]
        )
        #expect(records[2][1] == "Refund")
        #expect(records[2][4] == "120.00")
        #expect(
            Array(records[3][1...6]) == ["Transfer", "Everyday Savings", "Travel Euros", "1000.00", "10.50", "INR"]
        )
        #expect(records[4][5] == "")
    }

    @Test("The file is UTF-8 with a byte order mark and reads back through the importer unchanged")
    func roundTrip() throws {
        let data = TransactionCSVWriter.data(for: transactions(), lookup: lookup, dateStyle: .iso8601)
        #expect(Array(data.prefix(3)) == CSVWriter.byteOrderMark)
        let pipeline = DefaultImportPipeline()
        let file = try pipeline.open(data)
        let settings = ImportReadSettings(
            mapping: file.suggestedMapping,
            dateOrder: .yearMonthDay,
            decimalSeparator: .period,
            timeZone: F.timeZone(),
        )
        let ledger = F.ledger()
        let preview = pipeline.preview(
            rows: pipeline.rows(in: file, settings: settings),
            ledger: ledger,
            choices: ImportChoices(),
            settings: settings,
            defaultCurrency: "INR",
        )
        #expect(preview.failedCount == 0)
        let drafts = preview.rows.compactMap(\.draft)
        #expect(drafts.map(\.kind) == [.expense, .refund, .transfer, .transfer])
        #expect(drafts.map(\.amount) == transactions().map(\.amount))
        #expect(drafts[0].category == .existing(F.groceriesID))
        #expect(drafts[2].destinationAmount == F.dec("10.5"))
        #expect(drafts.map(\.date) == transactions().map(\.date))
    }

    @Test("D323.1: text cells starting with a formula character get an apostrophe that import removes again")
    func formulaProtectionRoundTrip() throws {
        let lantern = Payee(name: "=Lantern Tea House")
        let transaction = Transaction(
            type: .expense,
            amount: F.dec("500"),
            date: F.date(2026, 10, 24, 18),
            timeZoneID: F.zone,
            accountID: F.savingsID,
            categoryID: F.groceriesID,
            payeeID: lantern.id,
            details: "@Riverside stall",
            note: "-2 mugs",
        )
        let lookup = TransactionCSVLookup(
            accounts: F.accounts(),
            categories: F.categories(),
            payees: F.payees() + [lantern],
        )
        let records = TransactionCSVWriter.records(for: [transaction], lookup: lookup, dateStyle: .iso8601)
        #expect(
            records[1] == [
                "2026-10-24 18:00:00", "Expense", "Everyday Savings", "", "-500.00", "", "INR", "Food › Groceries",
                "'=Lantern Tea House", "'@Riverside stall", "'-2 mugs",
            ]
        )
        let text = TransactionCSVWriter.text(for: [transaction], lookup: lookup, dateStyle: .iso8601)
        #expect(text.contains(",-500.00,"))
        let rows = try F.rows(text)
        #expect(rows.count == 1)
        #expect(rows[0].issues.isEmpty)
        #expect(rows[0].payee == "=Lantern Tea House")
        #expect(rows[0].details == "@Riverside stall")
        #expect(rows[0].note == "-2 mugs")
        #expect(rows[0].amount == F.dec("500"))
        #expect(rows[0].kind == .expense)
    }

    @Test("D323.1: only formula characters are protected, and only one apostrophe is removed")
    func formulaProtectionRules() {
        for trigger in ["=", "+", "-", "@", "\t", "\r"] {
            #expect(TransactionCSVWriter.protectedText(trigger + "Sum") == "'" + trigger + "Sum")
        }
        #expect(TransactionCSVWriter.protectedText("\r\nNext line") == "'\r\nNext line")
        #expect(TransactionCSVWriter.protectedText("Tea = chai") == "Tea = chai")
        #expect(TransactionCSVWriter.protectedText("'Quoted") == "'Quoted")
        #expect(TransactionCSVWriter.protectedText("") == "")
        #expect(TransactionCSVWriter.unprotectedText("'=Sum") == "=Sum")
        #expect(TransactionCSVWriter.unprotectedText("''=Sum") == "''=Sum")
        #expect(TransactionCSVWriter.unprotectedText("'Quoted") == "'Quoted")
        #expect(TransactionCSVWriter.unprotectedText("'") == "'")
    }

    @Test("D323.1: an apostrophe in a number or date column isn't removed on import")
    func formulaProtectionSkipsNumbers() throws {
        let rows = try F.rows("Date,Amount,Payee\n2026-10-20,'-500.00,'+Corner Kiosk\n")
        #expect(rows[0].payee == "+Corner Kiosk")
        #expect(rows[0].issues == [.unreadableAmount])
    }

    @Test("Short dates follow the locale")
    func shortDate() {
        let records = TransactionCSVWriter.records(
            for: [transactions()[0]],
            lookup: lookup,
            dateStyle: .shortDate(Locale(identifier: "en_US_POSIX")),
        )
        #expect(records[1][0].contains("26"))
        #expect(!records[1][0].contains(":"))
    }

    @Test("Amount text keeps zero-decimal and three-decimal currencies exact")
    func amountText() {
        #expect(TransactionCSVWriter.amountText(F.dec("-1500"), currencyCode: "JPY") == "-1500")
        #expect(TransactionCSVWriter.amountText(F.dec("12.345"), currencyCode: "BHD") == "12.345")
        #expect(TransactionCSVWriter.amountText(F.dec("0.1"), currencyCode: "INR") == "0.10")
    }

    @Test("The export use case filters by account and day range, oldest first, and names the file")
    func exportUseCase() throws {
        let repository = try FakeLedgerRepository(accounts: F.accounts(), categories: F.categories())
        try repository.savePayee(F.payees()[0])
        for transaction in transactions().reversed() {
            try repository.saveTransaction(transaction)
        }
        let useCase = DefaultExportTransactionsUseCase(repository: repository)
        let today = CalendarDay(year: 2026, month: 10, day: 25)
        #expect(try useCase.count(TransactionExportOptions()) == 4)
        #expect(try useCase.count(TransactionExportOptions(accountIDs: [F.walletID])) == 1)
        let range = TransactionExportOptions(
            range: .days(
                from: CalendarDay(year: 2026, month: 10, day: 21),
                through: CalendarDay(year: 2026, month: 10, day: 22),
            )
        )
        let export = try useCase.export(range, locale: F.india, today: today)
        #expect(export.rowCount == 2)
        #expect(export.fileName == "little-orbit_2026-10-21_to_2026-10-22.csv")
        let all = try useCase.export(TransactionExportOptions(), locale: F.india, today: today)
        #expect(all.fileName == "little-orbit_2026-10-25.csv")
        let text = try CSVText.decode(all.data)
        #expect(text.components(separatedBy: "\r\n")[1].hasPrefix("2026-10-20 09:00:00,Expense"))
    }
}

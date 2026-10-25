import Foundation
import LittleOrbitDomain
import Testing

/// The Debit & Credit preset (#60): detection, amounts, dates, categories, notes, transfer pairing, reason
/// order and duplicates. Every name and amount is made up.
@Suite("Debit & Credit format (#60)")
struct DebitAndCreditFormatTests {
    typealias F = ImportFixture  // swiftlint:disable:this type_name

    static let header = #""Date","Description","Category","Payee","Notes","Account","Transfer Account","Amount""#

    /// One quoted line per row: date, description, category, payee, notes, account, transfer account, amount.
    static func file(_ rows: [[String]], header: String = header) -> String {
        let lines = rows.map { fields in
            fields.map { "\"" + $0.replacing("\"", with: "\"\"") + "\"" }.joined(separator: ",")
        }
        return ([header] + lines).joined(separator: "\r\n") + "\r\n"
    }

    static func row(
        _ date: String = "2026-04-10 09:00:00",
        description: String = "",
        category: String = "",
        payee: String = "Example Grocer",
        notes: String = "",
        account: String = "Everyday Savings",
        transfer: String = "",
        amount: String,
    ) -> [String] {
        [date, description, category, payee, notes, account, transfer, amount]
    }

    static func rows(_ text: String, zone: TimeZone = F.timeZone()) throws -> [ImportRow] {
        let table = try CSVReader.read(text)
        let format = DebitAndCreditFormat()
        let settings = ImportReadSettings(
            mapping: format.suggestedMapping(for: table.header),
            dateOrder: .dayMonthYear,
            decimalSeparator: .comma,
            timeZone: zone,
        )
        return format.rows(from: table, settings: settings)
    }

    static func preview(
        _ text: String,
        ledger: TransactionLedger = F.ledger(),
        choices: ImportChoices = ImportChoices(),
    ) throws -> ImportPreview {
        ImportPlanner.preview(
            rows: try rows(text),
            ledger: ledger,
            choices: choices,
            timeZone: F.timeZone(),
            defaultCurrency: "INR",
        )
    }

    // MARK: Detection (D44, D38.1)

    @Test("All 8 names in any order and case, with or without a BOM and extra columns, apply the preset")
    func detection() throws {
        let pipeline = DefaultImportPipeline(formats: ImportFormats(specific: [DebitAndCreditFormat()]))
        let shuffled =
            #""amount","TRANSFER ACCOUNT","account","Notes","payee"," Category ","Description","DATE","Tags","""#
        let file = try pipeline.open(Data(("\u{FEFF}" + shuffled + "\r\n").utf8))
        #expect(file.formatID == DebitAndCreditFormat.formatID)
        let mapping = file.suggestedMapping
        #expect(mapping.field(at: 0) == .amount)
        #expect(mapping.field(at: 1) == .toAccount)
        #expect(mapping.field(at: 7) == .date)
        #expect(mapping.field(at: 8) == nil)
        #expect(mapping.field(at: 9) == nil)

        let missing = #""Date","Description","Category","Notes","Account","Transfer Account","Amount""#
        #expect(try pipeline.open(Data((missing + "\n").utf8)).formatID == "generic")
        let misspelled = Self.header.replacing("Transfer Account", with: "Transfer Acount")
        #expect(try pipeline.open(Data((misspelled + "\n").utf8)).formatID == "generic")
    }

    // MARK: Amounts (D38.2, D39.1, D39.2)

    @Test("Accepted amounts are exact, with Western or Indian grouping, a sign and trailing zeros")
    func acceptedAmounts() {
        let cases: [(String, String)] = [
            ("1234.50", "1234.50"), ("1,234.5", "1234.5"), ("500", "500"), (" -980.00 ", "-980"),
            ("+1,234.50", "1234.50"), ("12,34,567.89", "1234567.89"), ("-1,00,000.00", "-100000"),
            ("1,00,00,000", "10000000"), ("1,234,567.89", "1234567.89"), ("0.01", "0.01"),
            ("999,999,999.99", "999999999.99"), ("1,234.500", "1234.5"),
        ]
        for (text, value) in cases {
            #expect(DebitAndCreditFormat.amount(text) == F.dec(value), "\(text)")
        }
    }

    @Test("Decimal commas, brackets, symbols, bad grouping and other text aren't read")
    func refusedAmounts() {
        for text in [
            "1.234,50", "(1,234.50)", "₹1,234.50", "1,234.5,0", "12 apples", "1,2,3.00", ",500.00", "500,.00",
            "1,,000", "1234,567", "123,45,678", "12,345,67.00", "", "-", "1.", "--5", "5-",
        ] {
            #expect(DebitAndCreditFormat.amount(text) == nil, "\(text)")
        }
    }

    @Test("Zero is “Amount is zero” and extra non-zero decimals are checked against the account's currency")
    func zeroAndDecimals() throws {
        let rows = try Self.rows(
            Self.file([
                Self.row(amount: "0"), Self.row(amount: "+0.00"), Self.row(amount: "-0.00"),
                Self.row(amount: "1.234"), Self.row(amount: "1,234.505"), Self.row(amount: "12 apples"),
            ])
        )
        #expect(rows[0].issues == [.zeroAmount])
        #expect(rows[1].issues == [.zeroAmount])
        #expect(rows[2].issues == [.zeroAmount])
        #expect(rows[5].issues == [.unreadableAmount])
        let preview = try Self.preview(
            Self.file([Self.row(amount: "1.234"), Self.row(amount: "1,234.505"), Self.row(amount: "-75.0000")])
        )
        #expect(preview.rows[0].issues == [.tooManyDecimalPlaces(currencyCode: "INR")])
        #expect(preview.rows[1].issues == [.tooManyDecimalPlaces(currencyCode: "INR")])
        #expect(preview.rows[2].draft?.amount == 75)
    }

    @Test("A new account's currency decides its decimals: BHD 1.234 and JPY 1500 (AM5, AM6)")
    func newAccountCurrency() throws {
        let text = Self.file([
            Self.row(account: "Rainy Day", amount: "1.234"), Self.row(account: "Yen Jar", amount: "1500.00"),
            Self.row(account: "Yen Jar", amount: "1500.5"),
        ])
        let choices = ImportChoices(newAccountCurrencies: ["rainy day": "BHD", "yen jar": "JPY"])
        let preview = try Self.preview(text, choices: choices)
        #expect(preview.rows[0].draft?.amount == F.dec("1.234"))
        #expect(preview.rows[1].draft?.amount == 1500)
        #expect(preview.rows[2].issues == [.tooManyDecimalPlaces(currencyCode: "JPY")])
        #expect(try Self.preview(text).rows[0].issues == [.tooManyDecimalPlaces(currencyCode: "INR")])
    }

    // MARK: Dates (D35.4, D38.3)

    @Test("Only YYYY-MM-DD HH:mm:ss is read, as a wall time in the device zone")
    func dates() throws {
        let rows = try Self.rows(
            Self.file([
                Self.row("2026-03-05 18:42:10", amount: "1"), Self.row("2026-02-30 10:00:00", amount: "1"),
                Self.row("2026-03-05", amount: "1"), Self.row("05/03/2026 18:42", amount: "1"),
                Self.row("2028-02-29 12:00:00", amount: "1"), Self.row("", amount: "1"),
            ])
        )
        let kolkata = ImportDateParser.date(
            ImportWallTime(year: 2026, month: 3, day: 5, hour: 18, minute: 42, second: 10),
            in: F.timeZone(),
        )
        #expect(rows[0].date == kolkata)
        #expect(rows[1].issues == [.unreadableDate])
        #expect(rows[2].issues == [.unreadableDate])
        #expect(rows[3].issues == [.unreadableDate])
        #expect(rows[4].issues.isEmpty)
        #expect(rows[5].issues == [.missingDate])
    }

    @Test("A time in a spring-forward gap moves forward; a repeated time is the first occurrence (T1–T3)")
    func daylightSaving() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let gap = try Self.rows(Self.file([Self.row("2026-03-08 02:30:00", amount: "1")]), zone: newYork)
        let twice = try Self.rows(Self.file([Self.row("2026-11-01 01:30:00", amount: "1")]), zone: newYork)
        let springLondon = try Self.rows(Self.file([Self.row("2026-03-29 01:15:00", amount: "1")]), zone: london)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        func instant(_ day: Int, _ month: Int, _ hour: Int, _ minute: Int) -> Date? {
            utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))
        }
        #expect(gap[0].date == instant(8, 3, 7, 30))  // 03:30 EDT
        #expect(twice[0].date == instant(1, 11, 5, 30))  // 01:30 EDT, UTC−4
        #expect(springLondon[0].date == instant(29, 3, 1, 15))  // 02:15 BST
    }

    // MARK: Categories (D36, D38.4, D39.3)

    @Test("Sub - Parent splits on the last ` - `, with each side trimmed and empty sides flat")
    func categories() throws {
        let values = [
            "Coffee - Food", "Tiles _ Flooring - Renovation", "  Coffee  -  Food  ", " - Food", "Coffee - ",
            "Wi-Fi - Bills", "Coffee-Food", " - ", "   ", "", "Snacks - Treats - Food", "Coffee – Food", "Coffee -Food",
        ]
        let rows = try Self.rows(Self.file(values.map { Self.row(category: $0, amount: "-1") }))
        let paths = rows.map(\.category)
        #expect(paths[0] == ImportCategoryPath(parent: "Food", name: "Coffee"))
        #expect(paths[1] == ImportCategoryPath(parent: "Renovation", name: "Tiles _ Flooring"))
        #expect(paths[2] == ImportCategoryPath(parent: "Food", name: "Coffee"))
        #expect(paths[3] == ImportCategoryPath(name: "Food"))
        #expect(paths[4] == ImportCategoryPath(name: "Coffee"))
        #expect(paths[5] == ImportCategoryPath(parent: "Bills", name: "Wi-Fi"))
        #expect(paths[6] == ImportCategoryPath(name: "Coffee-Food"))
        #expect(paths[7] == nil)
        #expect(paths[8] == nil)
        #expect(paths[9] == nil)
        #expect(paths[10] == ImportCategoryPath(parent: "Food", name: "Snacks - Treats"))
        #expect(paths[11] == ImportCategoryPath(name: "Coffee – Food"))
        #expect(paths[12] == ImportCategoryPath(name: "Coffee -Food"))
    }

    @Test("A flat Food and the parent Food are one category; income and expense are matched apart (C7, C8)")
    func categoryMatching() throws {
        let text = Self.file([
            Self.row(category: " - Food", amount: "-1"), Self.row(category: "  food ", amount: "-2"),
            Self.row(category: "Snacks - FOOD", amount: "-3"), Self.row(category: "Food", amount: "4"),
            Self.row(category: "Loan", amount: "5"), Self.row(category: "Loan", amount: "-6"),
        ])
        let ledger = TransactionLedger(accounts: F.accounts())
        let preview = try Self.preview(text, ledger: ledger)
        let expenseFood = ImportMatchKey(kind: .category(.expense), name: "Food")
        #expect(preview.rows[0].draft?.category == .new(expenseFood))
        #expect(preview.rows[1].draft?.category == .new(expenseFood))
        let snacks = ImportMatchKey(kind: .subcategory(.expense, parentKey: expenseFood.nameKey), name: "Snacks")
        #expect(preview.rows[2].draft?.category == .new(snacks))
        #expect(preview.rows[3].draft?.category == .new(ImportMatchKey(kind: .category(.income), name: "Food")))
        #expect(preview.rows[4].draft?.category != preview.rows[5].draft?.category)
        // Expense Food, Snacks, income Food and two Loans.
        #expect(preview.created(preview.defaultSelection).categories == 5)
    }

    @Test("Remapping the parent Food moves its subcategories with it (one choice)")
    func parentRemap() throws {
        let diningID = UUID()
        var ledger = F.ledger()
        ledger.categories.append(
            TransactionCategory(id: diningID, name: "Food & Dining", kind: .expense, sortOrder: 2)
        )
        let text = Self.file([Self.row(category: "Coffee - Fika", amount: "-1")])
        let parent = ImportMatchKey(kind: .category(.expense), name: "Fika")
        let preview = try Self.preview(
            text,
            ledger: ledger,
            choices: ImportChoices(matches: [parent: .existing(diningID)]),
        )
        #expect(preview.created(preview.defaultSelection).categories == 1)
        let child = ImportMatchKey(kind: .subcategory(.expense, parentKey: parent.nameKey), name: "Coffee")
        #expect(preview.rows[0].draft?.category == .new(child))
    }

    // MARK: Notes (D36, D38.6, D39.4)

    @Test("Description then Notes, the same text once, and over 2,000 characters shortened with a warning")
    func notes() throws {
        let family = "👨‍👩‍👧"
        let rows = try Self.rows(
            Self.file([
                Self.row(description: "Internet", notes: "Oct bill", amount: "-1"),
                Self.row(description: "Internet", amount: "-1"),
                Self.row(notes: "Oct bill", amount: "-1"),
                Self.row(description: "Monthly box ", notes: "  Monthly box", amount: "-1"),
                Self.row(description: "monthly box", notes: "Monthly box", amount: "-1"),
                Self.row(
                    description: String(repeating: "a", count: 1_000),
                    notes: String(repeating: "b", count: 999),
                    amount: "-1",
                ),
                Self.row(
                    description: String(repeating: "a", count: 1_000),
                    notes: String(repeating: "b", count: 1_000),
                    amount: "-1",
                ),
                Self.row(description: String(repeating: "a", count: 1_998) + family + "🇮🇳tail", amount: "-1"),
                Self.row(notes: "Paid “Ravi’s” share | split 50:50; ok", amount: "-1"),
                Self.row(description: String(repeating: "e\u{301}", count: 2_000), amount: "-1"),
            ])
        )
        #expect(rows[0].note == "Internet\nOct bill")
        #expect(rows[1].note == "Internet")
        #expect(rows[2].note == "Oct bill")
        #expect(rows[3].note == "Monthly box")
        #expect(rows[4].note == "monthly box\nMonthly box")
        #expect(rows[5].note?.count == 2_000)
        #expect(rows[5].warnings.isEmpty)
        #expect(rows[6].warnings == [.notesShortened])
        #expect(
            rows[6].note == String(repeating: "a", count: 1_000) + "\n" + String(repeating: "b", count: 998) + "…"
        )
        #expect(rows[7].note == String(repeating: "a", count: 1_998) + family + "…")
        #expect(rows[8].note == "Paid “Ravi’s” share | split 50:50; ok")
        #expect(rows[9].warnings.isEmpty)
        #expect(rows.allSatisfy { $0.details == nil })
    }

    // MARK: Transfers (D36, D38.5, D50)

    @Test("A negative amount goes from Account to Transfer Account; a positive one the other way")
    func transferDirection() throws {
        let rows = try Self.rows(
            Self.file([
                Self.row(category: "Bills", account: "Everyday", transfer: "Rainy Day", amount: "-5,000.00"),
                Self.row("2026-04-11 09:00:00", account: "Everyday", transfer: "Rainy Day", amount: "300"),
            ])
        )
        #expect(rows[0].kind == .transfer)
        #expect(rows[0].accountName == "Everyday")
        #expect(rows[0].toAccountName == "Rainy Day")
        #expect(rows[0].category == nil)
        #expect(rows[0].payee == nil)
        #expect(rows[1].accountName == "Rainy Day")
        #expect(rows[1].toAccountName == "Everyday")
    }

    @Test("Each transfer row is a half for the planner to pair: none are merged while reading (D330)")
    func transferHalves() throws {
        let out = Self.row(account: "Everyday", transfer: "Rainy Day", amount: "-5,000.00")
        let back = Self.row(account: "Rainy Day", transfer: "everyday", amount: "5,000.00")
        let rows = try Self.rows(Self.file([out, back, Self.row(amount: "-10.00")]))
        #expect(rows.map(\.transferHalf) == [.outgoing, .incoming, nil])
        #expect(rows.allSatisfy { $0.mergedRowNumbers.isEmpty })
        #expect(rows[0].transferColumns == [.date: 0, .amount: 7])
        #expect(rows[2].transferColumns.isEmpty)
    }

    @Test("Both halves become one transfer; each row pairs at most once, in file order (TR1–TR4)")
    func pairing() throws {
        let out = Self.row(account: "Everyday", transfer: "Rainy Day", amount: "-5,000.00")
        let back = Self.row(account: "Rainy Day", transfer: "everyday", amount: "5,000.00")
        let tr1 = try Self.preview(Self.file([out, back])).rows
        #expect(tr1.count == 1)
        #expect(tr1[0].id == 2)
        #expect(tr1[0].row.mergedRowNumbers == [3])
        #expect(try Self.preview(Self.file([out, out])).rows.count == 2)
        #expect(try Self.preview(Self.file([out, back, out, back])).rows.count == 2)
        let tr4 = try Self.preview(Self.file([out, out, back])).rows
        #expect(tr4.map(\.id) == [2, 3])
        #expect(tr4[0].row.mergedRowNumbers == [4])
        #expect(tr4[1].row.mergedRowNumbers.isEmpty)
    }

    @Test("The same account on both sides is a row error, also after a remap (TR6, TR8)")
    func sameAccount() throws {
        let preview = try Self.preview(
            Self.file([
                Self.row(account: "Everyday", transfer: "everyday", amount: "-2,000.00"),
                Self.row(account: "Everyday", transfer: "Main Purse", amount: "-2,000.00"),
            ])
        )
        #expect(preview.rows[0].issues == [.sameTransferAccount])
        #expect(preview.rows[1].issues.isEmpty)
        let remapped = try Self.preview(
            Self.file([Self.row(account: "Everyday Savings", transfer: "Main Purse", amount: "-2,000.00")]),
            choices: ImportChoices(matches: [
                ImportMatchKey(kind: .account, name: "Main Purse"): .existing(F.savingsID)
            ]),
        )
        #expect(remapped.rows[0].issues == [.sameTransferAccount])
    }

    @Test("A transfer between currencies is the D29 error, because the format has no Destination Amount")
    func currencies() throws {
        let preview = try Self.preview(
            Self.file([Self.row(account: "Everyday Savings", transfer: "Travel Euros", amount: "-100.00")])
        )
        #expect(preview.rows[0].issues == [.destinationAmountRequired])
    }

    // MARK: Reason order (D110, D111)

    @Test("Every reason is listed in the 8 columns' fixed order, whatever the file's order (TR12–TR16)")
    func reasonOrder() throws {
        let tr12 = Self.row(account: "Everyday", transfer: "Everyday", amount: "12 apples")
        let tr13 = Self.row("2026-02-30 10:00:00", account: "", amount: "0.00")
        let tr16 = Self.row(account: "Everyday", transfer: "Everyday", amount: "0.00")
        let standard = try Self.preview(Self.file([tr12, tr13, tr16]))
        #expect(standard.rows[0].issues == [.sameTransferAccount, .unreadableAmount])
        #expect(standard.rows[1].issues == [.unreadableDate, .missingAccount, .zeroAmount])
        #expect(standard.rows[2].issues == [.sameTransferAccount, .zeroAmount])

        let reversedHeader =
            #""Amount","Transfer Account","Account","Notes","Payee","Category","Description","Date","Tags""#
        let reversed = [tr12, tr13, tr16].map { Array($0.reversed()) + ["trip"] }
        let shuffled = try Self.preview(Self.file(reversed, header: reversedHeader))
        #expect(shuffled.rows.map(\.issues) == standard.rows.map(\.issues))
    }

    // MARK: Duplicates (D28, D42, D324.2)

    @Test("Identical rows in one file all import; a re-import is Already imported, by #60's narrower rule")
    func duplicates() throws {
        let text = Self.file([
            Self.row(
                "2026-06-12 08:30:00",
                category: "Coffee - Food",
                payee: "Bean Bar",
                account: "Corner Wallet",
                amount: "-120.00",
            ),
            Self.row(
                "2026-06-12 08:30:00",
                category: "Coffee - Food",
                payee: "Bean Bar",
                account: "Corner Wallet",
                amount: "-120.00",
            ),
        ])
        let first = try Self.preview(text)
        #expect(first.defaultSelection.count == 2)

        let coffeeID = UUID()
        var ledger = F.ledger()
        ledger.categories.append(
            TransactionCategory(id: coffeeID, name: "Coffee", kind: .expense, parentID: F.foodID, sortOrder: 2)
        )
        let existing = Transaction(
            type: .expense,
            amount: 120,
            date: try #require(first.rows[0].draft?.date),
            timeZoneID: F.zone,
            accountID: F.walletID,
            categoryID: coffeeID,
            payeeID: F.cornerShopID,  // A different payee: #60's rule doesn't compare it.
            details: "Edited description",
        )
        ledger.transactions = [existing]
        let again = try Self.preview(text, ledger: ledger)
        #expect(again.alreadyImportedCount == 2)
        #expect(again.defaultSelection.isEmpty)

        var edited = existing
        edited.note = "Added later"
        ledger.transactions = [edited]
        let close = try Self.preview(text, ledger: ledger)
        #expect(close.alreadyImportedCount == 0)
        #expect(close.possibleDuplicateCount == 0)
        #expect(close.defaultSelection.count == 2)
    }

    // MARK: Preview totals (#60 “Preview”)

    @Test("Totals per account count the ticked income and expense rows, without transfers")
    func totals() throws {
        let preview = try Self.preview(
            Self.file([
                Self.row(account: "Everyday Savings", amount: "1,000.00"),
                Self.row(account: "Everyday Savings", amount: "-250.50"),
                Self.row(account: "Cash", amount: "-40"),
                Self.row(account: "Everyday Savings", transfer: "Cash", amount: "-500"),
            ])
        )
        let totals = preview.totals(preview.defaultSelection)
        #expect(totals.count == 2)
        #expect(
            totals[0] == ImportAccountTotal(account: .existing(F.savingsID), income: 1_000, expense: F.dec("250.50"))
        )
        #expect(totals[1].expense == 40)
        let created = preview.created(preview.defaultSelection)
        #expect(created.accounts == 1)
        #expect(created.payees == 1)
        #expect(preview.totals([preview.rows[0].id]).count == 1)
    }
}

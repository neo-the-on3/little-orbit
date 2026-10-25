import Foundation
import LittleOrbitDomain
import Testing

/// Reading rows: types, signed or two-column amounts, and a clear issue per unreadable value (#30 AC 4, AC 7).
@Suite("Generic CSV rows (#30)")
struct GenericCSVFormatTests {
    typealias F = ImportFixture  // swiftlint:disable:this type_name

    @Test("A signed amount sets the type; a Type column wins and the amount is kept as a magnitude")
    func signedAmounts() throws {
        let rows = try F.rows(
            """
            Date,Amount,Payee
            2026-10-20,"-1,25,000.50",Corner Shop
            2026-10-21,(450),Corner Shop
            2026-10-22,2000,Employer
            """
        )
        #expect(rows.map(\.kind) == [.expense, .expense, .income])
        #expect(rows.map(\.amount) == [F.dec("125000.50"), 450, 2000])
        #expect(rows.allSatisfy { $0.issues.isEmpty })
    }

    @Test("Debit and credit columns: one filled gives the type; both filled conflict")
    func twoColumns() throws {
        let rows = try F.rows(
            """
            Date,Debit,Credit
            2026-10-20,450.00,
            2026-10-21,,2000
            2026-10-22,5,5
            2026-10-23,,
            """
        )
        #expect(rows[0].kind == .expense)
        #expect(rows[1].kind == .income)
        #expect(rows[2].issues == [.conflictingAmounts])
        #expect(rows[3].issues == [.missingAmount])
    }

    @Test("Each unreadable value gets its own issue, in column order")
    func issues() throws {
        let rows = try F.rows(
            """
            Date,Type,Amount
            32/13/2026,Gift,abc
            2026-10-20,Expense,0
            """
        )
        #expect(rows[0].issues == [.unreadableDate, .unknownType, .unreadableAmount])
        #expect(rows[0].rowNumber == 2)
        #expect(rows[1].issues == [.zeroAmount])
    }

    @Test("Refunds and transfers: a transfer drops category and payee and needs a To Account")
    func kinds() throws {
        let rows = try F.rows(
            """
            Date,Type,Account,To Account,Amount,Category,Payee
            2026-10-20,Refund,Everyday Savings,,200,Food › Groceries,Corner Shop
            2026-10-21,Transfer,Everyday Savings,Corner Wallet,500,Food,Corner Shop
            2026-10-22,Transfer,Everyday Savings,,500,,
            """
        )
        #expect(rows[0].kind == .refund)
        #expect(rows[0].category == ImportCategoryPath(parent: "Food", name: "Groceries"))
        #expect(rows[1].category == nil)
        #expect(rows[1].payee == nil)
        #expect(rows[1].toAccountName == "Corner Wallet")
        #expect(rows[2].issues == [.missingToAccount])
    }

    @Test("D105: a description over 100 characters is shortened with a warning, not refused")
    func shortened() throws {
        let long = String(repeating: "a", count: 140)
        let rows = try F.rows("Date,Amount,Description\n2026-10-20,-5,\(long)\n")
        #expect(rows[0].issues.isEmpty)
        #expect(rows[0].warnings == [.descriptionShortened])
        #expect((rows[0].details?.count ?? 0) <= 100)
    }

    @Test("A CRLF file's quoted line breaks read as LF, so no carriage return reaches the notes")
    func crlfLineBreaks() throws {
        let rows = try F.rows(
            "Date,Amount,Description,Notes\r\n"
                + "2026-10-20,-5,\"Tea\r\nand cake\",\"Line one\r\nline two\rline three\"\r\n"
                + "2026-10-21,-6,Kiosk,'=Sum\r\n"
        )
        #expect(rows.count == 2)
        #expect(rows[0].details == "Tea\nand cake")
        #expect(rows[0].note == "Line one\nline two\nline three")
        #expect(rows[0].note?.contains("\r") == false)
        #expect(rows[1].note == "=Sum")
    }

    @Test("A CR CR LF inside a quoted cell is one LF, with no carriage return left over")
    func doubledCarriageReturn() throws {
        let rows = try F.rows(
            "Date,Amount,Description,Notes\r\r\n"
                + "2026-10-20,-5,\"a\r\r\nb\",\"Line one\r\r\nline two\r\rline four\"\r\r\n"
        )
        #expect(rows.count == 1)
        #expect(rows[0].details == "a\nb")
        #expect(rows[0].note == "Line one\nline two\n\nline four")
        #expect(rows[0].note?.unicodeScalars.contains("\r") == false)
        #expect(ImportText.lineBreaks("a\r\r\nb") == "a\nb")
    }

    @Test("A short row is missing columns; an unclosed quote is flagged")
    func malformed() throws {
        let rows = try F.rows("Date,Amount,Payee\n2026-10-20\n2026-10-21,-5,\"Corner\n")
        #expect(rows[0].issues.contains(.missingColumns))
        #expect(rows[1].issues.contains(.unclosedQuote))
        // D349.2: the column where the quote opens.
        #expect(rows[1].issueColumn == 2)
    }

    @Test("D323.3: a row's first issue keeps its column, so Review can show the raw value")
    func issueColumn() throws {
        let rows = try F.rows("Date,Withdrawal,Payee\n2026-10-20,1.250/-,Kiosk\n2026-10-21\n2026-10-22,-5,Kiosk\n")
        #expect(rows[0].issues == [.unreadableAmount])
        #expect(rows[0].issueColumn == 1)
        #expect(rows[1].issues.first == .missingColumns)
        #expect(rows[1].issueColumn == nil)
        #expect(rows[2].issueColumn == nil)
    }
}

import Foundation
import LittleOrbitDomain
import Testing

/// Matching, the target account, per-row checks and duplicate flags (#30 AC 3, AC 5, AC 6, D18, D28, D42, D50).
@Suite("Import preview (#30)")
struct ImportPlannerTests {
    typealias F = ImportFixture  // swiftlint:disable:this type_name

    private let header =
        "Date,Type,Account,To Account,Amount,Destination Amount,Currency,Category,Payee,Description,Notes\n"

    @Test("Names match existing records case-insensitively; unknown names become new records")
    func matching() throws {
        let preview = try F.preview(
            header + """
                2026-10-20,Expense,everyday savings,,-450,,INR,food › groceries,CORNER SHOP,Milk,
                2026-10-21,Expense,New Card,,-90,,INR,Fun › Films,Cinema Hall,,
                """
        )
        let first = try #require(preview.rows[0].draft)
        #expect(first.account == .existing(F.savingsID))
        #expect(first.category == .existing(F.groceriesID))
        #expect(first.payee == .existing(F.cornerShopID))
        let second = try #require(preview.rows[1].draft)
        guard case .new = second.account, case .new = second.category, case .new = second.payee else {
            Issue.record("Expected new records for unknown names")
            return
        }
        #expect(
            preview.matches.filter { $0.choice == .new }.map(\.name) == ["New Card", "Fun", "Films", "Cinema Hall"]
        )
    }

    @Test("Without an Account column, rows go to the chosen account; with none chosen, they can't import")
    func targetAccount() throws {
        let text = "Date,Amount\n2026-10-20,-450\n"
        let chosen = try F.preview(text, choices: ImportChoices(targetAccountID: F.walletID))
        #expect(chosen.rows[0].draft?.account == .existing(F.walletID))
        let none = try F.preview(text)
        #expect(none.rows[0].status == .failed([.missingAccount]))
    }

    @Test("Currency, decimals and transfer rules are checked against the matched account")
    func checks() throws {
        let preview = try F.preview(
            header + """
                2026-10-20,Expense,Everyday Savings,,-450,,EUR,,,,
                2026-10-20,Expense,Everyday Savings,,-4.505,,INR,,,,
                2026-10-20,Transfer,Everyday Savings,Everyday Savings,100,,INR,,,,
                2026-10-20,Transfer,Everyday Savings,Travel Euros,1000,,INR,,,,
                2026-10-20,Transfer,Everyday Savings,Travel Euros,1000,10.50,INR,,,,
                2026-10-20,Transfer,Everyday Savings,Corner Wallet,100,,INR,,,,
                """
        )
        #expect(preview.rows[0].status == .failed([.currencyMismatch(accountCurrency: "INR")]))
        #expect(preview.rows[1].status == .failed([.tooManyDecimalPlaces(currencyCode: "INR")]))
        #expect(preview.rows[2].status == .failed([.sameTransferAccount]))
        #expect(preview.rows[3].status == .failed([.destinationAmountRequired]))
        #expect(preview.rows[4].draft?.destinationAmount == F.dec("10.50"))
        #expect(preview.rows[5].status == .ready)
        #expect(preview.rows[5].draft?.destinationAmount == nil)
        #expect(preview.failedCount == 4)
    }

    @Test("D42: the exact same transaction is Already imported; a near one is a Possible duplicate; neither is ticked")
    func duplicates() throws {
        let existing = Transaction(
            type: .expense,
            amount: 450,
            date: F.date(2026, 10, 20),
            timeZoneID: F.zone,
            accountID: F.savingsID,
            categoryID: F.groceriesID,
            payeeID: F.cornerShopID,
            details: "Milk",
        )
        let preview = try F.preview(
            header + """
                2026-10-20,Expense,Everyday Savings,,-450,,INR,Food › Groceries,Corner Shop,Milk,
                2026-10-22,Expense,Everyday Savings,,-450,,INR,,Corner Shop Ltd,,
                2026-10-24,Expense,Everyday Savings,,-450,,INR,,Corner Shop,,
                2026-10-20,Income,Everyday Savings,,450,,INR,,Corner Shop,,
                2026-10-20,Expense,Corner Wallet,,-450,,INR,,Corner Shop,,
                """,
            ledger: F.ledger([existing]),
        )
        #expect(preview.rows[0].status == .alreadyImported(existingID: existing.id))
        #expect(preview.rows[1].status == .possibleDuplicate(existingID: existing.id))
        #expect(preview.rows[2].status == .ready)  // 4 days apart
        #expect(preview.rows[3].status == .ready)  // a different type
        #expect(preview.rows[4].status == .ready)  // a different account
        #expect(preview.defaultSelection == [preview.rows[2].id, preview.rows[3].id, preview.rows[4].id])
        #expect(preview.alreadyImportedCount == 1)
        #expect(preview.possibleDuplicateCount == 1)
    }

    @Test("D28: rows in the same file are never duplicates of each other")
    func sameFile() throws {
        let preview = try F.preview(
            header + """
                2026-10-20,Expense,Everyday Savings,,-450,,INR,,Corner Shop,,
                2026-10-20,Expense,Everyday Savings,,-450,,INR,,Corner Shop,,
                """
        )
        #expect(preview.rows.map(\.status) == [.ready, .ready])
    }

    @Test("A user's change to a match is applied")
    func remap() throws {
        let text = header + "2026-10-20,Expense,Old Card,,-450,,INR,,,,\n"
        let key = ImportMatchKey(kind: .account, name: "Old Card")
        let preview = try F.preview(text, choices: ImportChoices(matches: [key: .existing(F.walletID)]))
        #expect(preview.rows[0].draft?.account == .existing(F.walletID))
        #expect(preview.matches.first?.isRemapped == true)
    }
}

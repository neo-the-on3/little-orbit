import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

@Suite("I17 import accessibility presentation")
@MainActor
struct CSVImportAccessibilityTests {
    @Test("Columns expose their source header and the current mapped field, including Don’t Import")
    func columns() async throws {
        let model = CSVFixture.model(try CSVFixture.repository())
        await model.open(
            data: Data("Date,Details,Amount\n2026-10-05,Metro Ticket,-12.50\n".utf8),
            fileName: "maple_oct.csv",
        )
        #expect(model.columnRows[0].header == "Date")
        #expect(model.columnRows[0].accessibilityValue == "Date")
        model.setField(nil, forColumn: 0)
        #expect(model.columnRows[0].accessibilityValue == "Don’t Import")
        model.setField(.payee, forColumn: 0)
        #expect(model.columnRows[0].accessibilityValue == "Payee")
    }

    @Test("Match exposes the file value and a choice resolved by identity, not by the file’s name")
    func matches() async throws {
        let repository = try CSVFixture.repository()
        let model = CSVFixture.model(repository)
        await model.open(
            data: Data("Date,Amount,Account,Payee,Category\n2026-10-05,-12.50,Travel Card,Corner Bakery,Food\n".utf8),
            fileName: "maple_oct.csv",
        )
        await model.next()
        let account = try #require(model.accountMatches.first)
        #expect(account.name == "Travel Card")
        #expect(account.accessibilityCurrencyLabel == "Currency for Travel Card")
        #expect(account.accessibilityValue == "Create New")
        #expect(model.payeeMatches.first?.name == "Corner Bakery")
        #expect(model.payeeMatches.first?.accessibilityValue == "Create New")
        #expect(model.categoryMatches.first?.name == "Food")
        #expect(model.categoryMatches.first?.accessibilityValue == "Create New")
        let existing = try CSVFixture.account("Everyday Savings", in: repository)
        await model.setChoice(.existing(existing.id), for: account.id)
        #expect(model.accountMatches.first?.name == "Travel Card")
        #expect(model.accountMatches.first?.accessibilityValue == "Everyday Savings")
    }

    @Test("Review speaks one whole phrase and updates it when selection changes")
    func review() async throws {
        let repository = try CSVFixture.repository()
        let model = CSVFixture.model(repository)
        await model.open(
            data: Data(
                "Date,Amount,Account\n2026-10-05,-12.50,Everyday Savings\n2026-10-06,-3,Everyday Savings\n2026-10-07,-4,Everyday Savings\n"
                    .utf8
            ),
            fileName: "riverstone_oct.csv",
        )
        await model.next()
        await model.next()
        #expect(model.step == .review)
        #expect(model.accessibilityReviewCounts.map(\.count) == [3, 0, 0, 0, 0])
        #expect(model.accessibilityReviewCounts.first?.spoken == "3 to import")
        #expect(model.canImport)
        for row in model.selectedRows { model.toggle(row.id) }
        #expect(model.accessibilityReviewCounts.first?.spoken == "0 to import")
        #expect(!model.canImport)
    }

    @Test("Each Review count has a singular whole phrase, not a separately read label and value")
    func singularCounts() {
        let kinds: [ImportReviewCount.Kind] = [
            .toImport, .cantImport, .shortened, .alreadyImported, .possibleDuplicates, .accounts, .categories, .payees,
        ]
        let phrases = [
            "1 to import", "1 can’t be imported", "1 shortened", "1 already imported", "1 possible duplicate",
            "1 new account", "1 new category", "1 new payee",
        ]
        for (kind, phrase) in zip(kinds, phrases) {
            #expect(ImportReviewCount(kind: kind, count: 1).spoken == phrase)
        }
        #expect(ImportReviewCount(kind: .possibleDuplicates, count: 3).spoken == "3 possible duplicates")
        #expect(ImportReviewCount(kind: .accounts, count: 0).spoken == "0 new accounts")
    }
}

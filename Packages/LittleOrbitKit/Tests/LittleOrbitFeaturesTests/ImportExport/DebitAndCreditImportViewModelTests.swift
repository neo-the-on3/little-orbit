import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// The import sheet with the Debit & Credit preset registered as the App root does (#60), over the made-up
/// `Debit and Credit Export.csv`.
@Suite("Debit & Credit import screen (#60)")
@MainActor
struct DebitAndCreditImportViewModelTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    static let fileName = "Debit and Credit Export.csv"

    static func repository() throws -> InMemoryLedgerRepository {
        let repository = InMemoryLedgerRepository()
        try repository.saveAccount(Account(name: "Primary", type: .checking, currencyCode: "INR", sortOrder: 1))
        try repository.saveCategory(TransactionCategory(name: "Food & Dining", kind: .expense))
        try repository.saveCategory(TransactionCategory(name: "Salary", kind: .income))
        return repository
    }

    static func model(_ repository: InMemoryLedgerRepository) -> CSVImportViewModel {
        CSVImportViewModel(
            useCases: ImportUseCases(
                repository: repository,
                formats: ImportFormats(specific: [DebitAndCreditFormat()]),
            ),
            defaultCurrency: "INR",
            locale: F.india,
            timeZone: F.zone,
        )
    }

    static func review(_ repository: InMemoryLedgerRepository) async throws -> CSVImportViewModel {
        let model = model(repository)
        await model.open(data: try F.data("Debit and Credit Export"), fileName: fileName)
        await model.next()
        await model.next()
        return model
    }

    @Test("The preset maps every column, explains itself and hides the date and decimal pickers")
    func detection() async throws {
        let model = Self.model(try Self.repository())
        await model.open(data: try F.data("Debit and Credit Export"), fileName: Self.fileName)
        #expect(model.step == .columns)
        #expect(model.isDebitAndCredit)
        #expect(
            model.columnRows.map(\.field)
                == [.date, .description, .category, .payee, .notes, .account, .toAccount, .amount]
        )
        #expect(model.formatNote == ImportExportText.debitAndCreditDetected)
        #expect(!model.showsReadFormat)
        #expect(!model.needsTargetAccount)
    }

    @Test("Match: names are matched case-insensitively; a new account gets the region's currency")
    func match() async throws {
        let model = Self.model(try Self.repository())
        await model.open(data: try F.data("Debit and Credit Export"), fileName: Self.fileName)
        await model.next()
        #expect(model.step == .match)
        let accounts = model.accountMatches
        #expect(accounts.first { $0.name == "Primary" }?.newAccountCurrency == nil)
        let cash = try #require(accounts.first { $0.name == "Cash" })
        #expect(cash.choice == .new)
        #expect(cash.newAccountCurrency == "INR")
        #expect(model.accountsHeaderNote == ImportExportText.newAccountCurrencyNote)
        #expect(model.accountsFooterNote == ImportExportText.differentCurrenciesNote)
        #expect(model.currencyOptions.first == "INR")
    }

    @Test("Review: ready and failed rows, every reason in order, the paired transfer and the preview totals")
    func review() async throws {
        let model = try await Self.review(try Self.repository())
        #expect(model.step == .review)
        #expect(model.readyCount == 11)
        #expect(model.failedCount == 2)
        #expect(
            model.failedRows.map(\.reasons) == [
                ["Unrecognised amount"],
                ["Transfer Account must differ from Account", "Amount is zero"],
            ]
        )
        let transfer = try #require(model.selectedRows.first { $0.id == 7 })
        #expect(transfer.detail.hasPrefix("Rows 7 and 8"))
        #expect(model.createdCounts == ImportCreatedCounts(accounts: 2, categories: 10, payees: 9))
        #expect(model.accountTotals.map(\.name) == ["Primary", "Cash"])
        let primary = try #require(model.accountTotals.first)
        #expect(primary.income.contains("1,25,000"))
        #expect(primary.expense.contains("21,678"))
        #expect(model.notSelectedFooter == ImportExportText.debitAndCreditNotSelectedFooter)
    }

    @Test("Remapping the parent Food to an existing category creates one category fewer")
    func remap() async throws {
        let repository = try Self.repository()
        let model = Self.model(repository)
        await model.open(data: try F.data("Debit and Credit Export"), fileName: Self.fileName)
        await model.next()
        let food = try #require(model.categoryMatches.first { $0.name == "Food" })
        let dining = try #require(food.options.first { $0.name == "Food & Dining" })
        await model.setChoice(.existing(dining.id), for: food.id)
        await model.next()
        #expect(model.createdCounts.categories == 9)
    }

    @Test("D330: a new account in another currency merges both halves into one transfer between currencies")
    func currency() async throws {
        let model = Self.model(try Self.repository())
        await model.open(data: try F.data("Debit and Credit Export"), fileName: Self.fileName)
        await model.next()
        let savings = try #require(model.accountMatches.first { $0.name == "Savings" })
        await model.setCurrency("EUR", forNewAccount: savings.id)
        #expect(model.accountMatches.first { $0.name == "Savings" }?.newAccountCurrency == "EUR")
        await model.next()
        #expect(model.failedCount == 2)
        #expect(model.readyCount == 11)
        let transfer = try #require(model.preview?.rows.first { $0.id == 7 })
        #expect(transfer.row.mergedRowNumbers == [8])
        #expect(transfer.draft?.amount == 5_000)
        #expect(transfer.draft?.destinationAmount == 5_000)
        model.back()
        await model.setCurrency("INR", forNewAccount: savings.id)
        await model.next()
        #expect(model.failedCount == 2)
        #expect(model.preview?.rows.first { $0.id == 7 }?.draft?.destinationAmount == nil)
    }

    /// Two halves of one transfer, 90 seconds apart, the incoming half first: ₹1,000.00 from Primary arriving as
    /// $12.00 in the new account Travel Wallet once it's USD.
    static let halves = Data(
        ([
            #""Date","Description","Category","Payee","Notes","Account","Transfer Account","Amount""#,
            #""2026-05-01 10:00:00","Arrived","","","","Travel Wallet","Primary","12.00""#,
            #""2026-05-01 10:01:30","Trip money","","","","Primary","Travel Wallet","-1,000.00""#,
        ]
        .joined(separator: "\r\n") + "\r\n")
        .utf8
    )

    @Test("D330: same-currency halves with other amounts are under Can't Import, can't be ticked, and merge on USD")
    func mismatchedHalves() async throws {
        let model = Self.model(try Self.repository())
        await model.open(data: Self.halves, fileName: Self.fileName)
        await model.next()
        #expect(model.accountsFooterNote == ImportExportText.differentCurrenciesNote)
        let travel = try #require(model.accountMatches.first { $0.name == "Travel Wallet" })
        #expect(model.currencyTitle(for: "INR") == "INR — Indian Rupee")
        await model.next()
        #expect(model.failedCount == 2)
        #expect(model.readyCount == 0)
        let reason = "Transfer amounts don’t match — check the new account’s currency"
        #expect(model.failedRows.map(\.id) == [2, 3])
        #expect(model.failedRows.map(\.reasons) == [[reason], [reason]])
        #expect(model.failedRows.map(\.source) == [#"Amount: “12.00”"#, #"Amount: “-1,000.00”"#])
        #expect(model.failedRows.allSatisfy { !$0.isSelectable })
        for row in model.failedRows {
            model.toggle(row.id)
        }
        #expect(model.readyCount == 0)
        #expect(model.selectedRows.isEmpty)

        model.back()
        await model.setCurrency("USD", forNewAccount: travel.id)
        await model.next()
        #expect(model.failedCount == 0)
        #expect(model.readyCount == 1)
        let merged = try #require(model.selectedRows.first)
        #expect(merged.detail.hasPrefix("Rows 2 and 3"))
        #expect(merged.amount.contains("1,000"))
    }

    @Test("Import, then Undo; importing the file again finds every row Already imported")
    func commitAndUndo() async throws {
        let repository = try Self.repository()
        let model = try await Self.review(repository)
        await model.commit()
        #expect(model.step == .summary)
        let transactions = try repository.transactions()
        #expect(transactions.count == 11)
        #expect(transactions.filter { $0.type == .transfer }.count == 1)
        #expect(transactions.contains { $0.note == "Morning coffee\nOat milk ☕️ — extra hot" })
        #expect(transactions.contains { $0.note == "Groceries\nMilk\nBread" })
        let coffee = try #require(transactions.first { $0.note?.hasPrefix("Morning coffee") == true })
        #expect(coffee.date == Date(timeIntervalSince1970: 1_792_467_900))
        #expect(try repository.accounts().count == 3)

        let again = try await Self.review(repository)
        #expect(again.alreadyImportedCount == 11)
        #expect(again.readyCount == 0)

        model.requestUndo()
        model.undo()
        #expect(model.isUndone)
        #expect(try repository.transactions().isEmpty)
        #expect(try repository.accounts().count == 1)
        #expect(try repository.categories().count == 2)
        #expect(try repository.payees().isEmpty)
    }
}

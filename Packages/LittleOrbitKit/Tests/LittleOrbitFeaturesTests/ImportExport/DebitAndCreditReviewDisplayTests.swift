import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// What Match and Review show for a Debit & Credit file (#60): each name's row count, the amount a transfer
/// between currencies gives, the currencies rows use, and totals built once per tick change.
@Suite("Debit & Credit Match and Review display (#60)")
@MainActor
struct DebitAndCreditReviewDisplayTests {
    typealias D = DebitAndCreditImportViewModelTests  // swiftlint:disable:this type_name

    static func file(_ rows: [String]) -> Data {
        Data(
            ([#""Date","Description","Category","Payee","Notes","Account","Transfer Account","Amount""#] + rows)
                .joined(separator: "\r\n").appending("\r\n").utf8
        )
    }

    private func row(_ model: CSVImportViewModel, id: Int) -> ImportReviewRow? {
        (model.selectedRows + model.unselectedRows + model.failedRows).first { $0.id == id }
    }

    @Test("Match shows each name's row count, both halves of a transfer included, and keeps it after a re-plan")
    func matchRowCount() async throws {
        let model = D.model(try D.repository())
        await model.open(data: try CSVFixture.data("Debit and Credit Export"), fileName: D.fileName)
        await model.next()
        let savings = try #require(model.accountMatches.first { $0.name == "Savings" })
        #expect(savings.detail == "2 rows")
        let coffee = try #require(model.categoryMatches.first { $0.name.hasSuffix("Coffee") })
        #expect(coffee.detail == "1 row")
        let rows = model.accountMatches + model.categoryMatches + model.payeeMatches
        #expect(rows.allSatisfy { $0.detail?.hasSuffix(" row") == true || $0.detail?.hasSuffix(" rows") == true })
        await model.setCurrency("EUR", forNewAccount: savings.id)
        #expect(model.accountMatches.first { $0.name == "Savings" }?.detail == "2 rows")
    }

    @Test("A merged transfer between currencies says what it gives the other account; one currency says nothing")
    func receivedAmount() async throws {
        let model = D.model(try D.repository())
        await model.open(data: try CSVFixture.data("Debit and Credit Export"), fileName: D.fileName)
        await model.next()
        let savings = try #require(model.accountMatches.first { $0.name == "Savings" })
        await model.setCurrency("EUR", forNewAccount: savings.id)
        await model.next()
        let transfer = try #require(row(model, id: 7))
        #expect(transfer.detail == "Rows 7 and 8 · 15 Oct 2026 · Primary · received €5,000.00")
        #expect(transfer.amount.contains("5,000.00"))
        #expect(model.selectedRows.filter { $0.detail.contains("received") }.map(\.id) == [7])

        model.back()
        await model.setCurrency("INR", forNewAccount: savings.id)
        await model.next()
        #expect(row(model, id: 7)?.detail == "Rows 7 and 8 · 15 Oct 2026 · Primary")
    }

    @Test("An existing account in another currency: its rows and the amount it receives use its own currency")
    func existingAccountInOtherCurrency() async throws {
        let repository = try D.repository()
        try repository.saveAccount(Account(name: "Travel Wallet", type: .cash, currencyCode: "USD", sortOrder: 2))
        let model = D.model(repository)
        await model.open(
            data: Self.file([
                #""2026-05-01 10:00:00","Arrived","","","","Travel Wallet","Primary","12.00""#,
                #""2026-05-01 10:01:30","Trip money","","","","Primary","Travel Wallet","-1,000.00""#,
                #""2026-05-02 09:00:00","Snacks","","","","Travel Wallet","","-3.50""#,
            ]),
            fileName: D.fileName,
        )
        await model.next()
        #expect(model.accountMatches.allSatisfy { $0.newAccountCurrency == nil })
        await model.next()
        let transfer = try #require(row(model, id: 2))
        #expect(transfer.amount.contains("₹"))
        #expect(transfer.detail.hasPrefix("Rows 2 and 3"))
        #expect(transfer.detail.hasSuffix("received $12.00"))
        let snacks = try #require(row(model, id: 4))
        #expect(!snacks.amount.contains("₹"))
        #expect(snacks.amount.contains("3.50"))
        #expect(model.accountTotals.first { $0.name == "Travel Wallet" }?.currencyCode == "USD")
    }

    @Test("New accounts: each row takes its own account's currency, and the received amount the other account's")
    func newAccountsCurrencyByMatch() async throws {
        let model = D.model(try D.repository())
        await model.open(
            data: Self.file([
                #""2026-05-01 10:00:00","Out","","","","Cash Box","Euro Pot","-900.00""#,
                #""2026-05-01 10:00:30","In","","","","Euro Pot","Cash Box","10.00""#,
                #""2026-05-02 09:00:00","Tea","","","","Cash Box","","-40.00""#,
                #""2026-05-02 09:30:00","Bread","","","","Euro Pot","","-2.00""#,
            ]),
            fileName: D.fileName,
        )
        await model.next()
        let pot = try #require(model.accountMatches.first { $0.name == "Euro Pot" })
        await model.setCurrency("EUR", forNewAccount: pot.id)
        #expect(model.accountMatches.first { $0.name == "Cash Box" }?.newAccountCurrency == "INR")
        await model.next()
        let transfer = try #require(row(model, id: 2))
        #expect(transfer.amount.contains("₹"))
        #expect(transfer.amount.contains("900.00"))
        #expect(transfer.detail.hasSuffix("received €10.00"))
        #expect(try #require(row(model, id: 4)).amount.contains("₹"))
        let bread = try #require(row(model, id: 5))
        #expect(!bread.amount.contains("₹"))
        #expect(bread.amount.contains("€"))
        #expect(
            model.accountTotals.map { "\($0.name) \($0.currencyCode)" }.sorted() == ["Cash Box INR", "Euro Pot EUR"]
        )
    }

    @Test("A selectable row that isn't ticked lists only its own message as its reason")
    func unticked() async throws {
        let repository = try D.repository()
        let first = try await D.review(repository)
        await first.commit()
        let again = try await D.review(repository)
        #expect(again.unselectedRows.count == 11)
        #expect(again.unselectedRows.allSatisfy { $0.isSelectable && $0.reasons == [ImportExportText.alreadyImported] })

        let fresh = try await D.review(try D.repository())
        let coffee = try #require(fresh.selectedRows.first { $0.id == 2 })
        #expect(coffee.reasons.isEmpty)
        fresh.toggle(2)
        let unticked = try #require(fresh.unselectedRows.first { $0.id == 2 })
        #expect(unticked.reasons.isEmpty)
        #expect(unticked.message == nil)
    }

    @Test("Will Be Created and Totals by Account are built once per tick change or plan, not on every read")
    func totalsBuiltOncePerChange() async throws {
        let model = try await D.review(try D.repository())
        let builds = model.reviewTotalsBuilds
        #expect(builds > 0)
        for _ in 0..<5 {
            _ = model.createdCounts
            _ = model.accountTotals
        }
        #expect(model.reviewTotalsBuilds == builds)

        let salary = try #require(model.selectedRows.first { $0.id == 3 })
        model.toggle(salary.id)
        #expect(model.reviewTotalsBuilds == builds + 1)
        #expect(model.accountTotals.first { $0.name == "Primary" }?.income.contains("1,25,000") == false)
        model.toggle(salary.id)
        #expect(model.reviewTotalsBuilds == builds + 2)
        #expect(model.accountTotals.first { $0.name == "Primary" }?.income.contains("1,25,000") == true)

        model.back()
        let savings = try #require(model.accountMatches.first { $0.name == "Savings" })
        await model.setCurrency("EUR", forNewAccount: savings.id)
        #expect(model.reviewTotalsBuilds == builds + 3)
        #expect(model.createdCounts == ImportCreatedCounts(accounts: 2, categories: 10, payees: 9))
    }

    @Test("A setting change clears Will Be Created and Totals by Account, and the next plan builds them again")
    func totalsClearedBySettingChange() async throws {
        let model = try await D.review(try D.repository())
        #expect(model.createdCounts == ImportCreatedCounts(accounts: 2, categories: 10, payees: 9))
        #expect(!model.accountTotals.isEmpty)
        let builds = model.reviewTotalsBuilds

        model.back()
        model.back()
        #expect(model.step == .columns)
        let category = try #require(model.columnRows.first { $0.field == .category })
        model.setField(nil, forColumn: category.id)
        #expect(model.createdCounts == ImportCreatedCounts())
        #expect(model.accountTotals.isEmpty)

        await model.next()
        await model.next()
        #expect(model.step == .review)
        #expect(model.reviewTotalsBuilds > builds)
        #expect(model.createdCounts == ImportCreatedCounts(accounts: 2, categories: 0, payees: 9))
        #expect(model.accountTotals.map(\.name).sorted() == ["Cash", "Primary"])
    }

    @Test("An account renamed in another window: the re-plan builds Totals by Account again with the new name")
    func totalsReplannedAfterRenameElsewhere() async throws {
        let repository = try D.repository()
        var wallet = Account(name: "Travel Wallet", type: .cash, currencyCode: "INR", sortOrder: 2)
        try repository.saveAccount(wallet)
        let model = D.model(repository)
        await model.open(data: try CSVFixture.data("Debit and Credit Export"), fileName: D.fileName)
        await model.next()
        let cash = try #require(model.accountMatches.first { $0.name == "Cash" })
        await model.setChoice(.existing(wallet.id), for: cash.id)
        await model.next()
        #expect(model.step == .review)
        #expect(model.accountTotals.map(\.name).sorted() == ["Primary", "Travel Wallet"])
        let created = model.createdCounts
        let builds = model.reviewTotalsBuilds

        wallet.name = "Pocket Money"
        try repository.saveAccount(wallet)
        await model.dataChanged()
        #expect(model.dataChangedNotice != nil)
        #expect(model.reviewTotalsBuilds > builds)
        #expect(model.accountTotals.map(\.name).sorted() == ["Pocket Money", "Primary"])
        #expect(model.createdCounts == created)
    }
}

import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Review's rows as `ImportRowFormatter` builds them with each plan: a Debit & Credit file's own wording and
/// new-account currencies (#60), and a #30 file left as it was.
@Suite("Import row formatter by format (#30, #60)")
@MainActor
struct ImportRowFormatterFormatTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    /// One expense in an account the import creates, so its amount takes the currency picked on Match.
    static let newAccountRow = Data(
        ([
            #""Date","Description","Category","Payee","Notes","Account","Transfer Account","Amount""#,
            #""2026-05-01 10:00:00","Snacks","","","","Travel Wallet","","-12.50""#,
        ]
        .joined(separator: "\r\n") + "\r\n")
        .utf8
    )

    private func reviewRow(_ model: CSVImportViewModel, id: Int) -> ImportReviewRow? {
        (model.selectedRows + model.unselectedRows + model.failedRows).first { $0.id == id }
    }

    @Test("Debit & Credit: a new account's row shows its amount in the currency picked on Match")
    func newAccountCurrency() async throws {
        let repository = try DebitAndCreditImportViewModelTests.repository()
        let model = DebitAndCreditImportViewModelTests.model(repository)
        await model.open(data: Self.newAccountRow, fileName: DebitAndCreditImportViewModelTests.fileName)
        await model.next()
        let wallet = try #require(model.accountMatches.first { $0.name == "Travel Wallet" })
        #expect(wallet.newAccountCurrency == "INR")
        await model.next()
        let inRupees = try #require(reviewRow(model, id: 2))
        #expect(inRupees.amount.contains("₹"))
        #expect(inRupees.detail.hasPrefix("Row 2"))

        model.back()
        await model.setCurrency("USD", forNewAccount: wallet.id)
        #expect(model.accountMatches.first { $0.name == "Travel Wallet" }?.newAccountCurrency == "USD")
        await model.next()
        let inDollars = try #require(reviewRow(model, id: 2))
        #expect(!inDollars.amount.contains("₹"))
        #expect(inDollars.amount.contains("12.50"))
    }

    @Test("#30: one reason in #30's wording, single-row details, no new-account currency and #30's footer")
    func genericFileUnchanged() async throws {
        let repository = try F.repository()
        let model = F.model(repository, changes: F.Changes())
        await model.open(data: try F.data("Bank Statement Debit Credit"), fileName: "Bank Statement Debit Credit.csv")
        #expect(!model.isDebitAndCredit)
        await model.next()
        model.targetAccountID = try F.account("Everyday Savings", in: repository).id
        await model.next()
        #expect(model.step == .review)
        #expect(model.failedRows.map(\.reasons) == [["Amount is zero"]])
        #expect(model.failedRows.map(\.message) == ["Amount is zero"])
        #expect(model.selectedRows.allSatisfy { $0.detail.hasPrefix("Row ") && $0.reasons.isEmpty })
        #expect((model.accountMatches + model.categoryMatches).allSatisfy { $0.newAccountCurrency == nil })
        #expect((model.accountMatches + model.categoryMatches + model.payeeMatches).allSatisfy { $0.detail == nil })
        #expect(model.selectedRows.allSatisfy { !$0.detail.contains("received") })
        #expect(model.notSelectedFooter == ImportExportText.notSelectedFooter)
    }
}

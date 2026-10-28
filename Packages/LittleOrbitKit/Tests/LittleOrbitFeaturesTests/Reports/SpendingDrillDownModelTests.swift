import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

@MainActor
@Suite("Spending report drill-down refresh (#27 core)")
struct SpendingDrillDownModelTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name

    @Test("Given an open drill-down, when the store revision changes after a deletion, then its rows and total update")
    func refreshAfterDeletion() throws {
        let deleted = S.expense("2000", S.groceries, 10, 3, payee: S.payee)
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([
                deleted,
                S.expense("450.50", S.groceries, 10, 7),
                S.expense("25000", S.rent, 10, 1),
            ])
        )
        let report = S.model(fake)
        report.load(at: 0)
        let row = try #require(report.rows.first { $0.categoryID == S.groceries.id })
        let drill = report.makeDrillDown(for: row)
        drill.load()
        #expect(drill.drillDown?.entries.count == 2)
        #expect(drill.drillDown?.amountText == "₹2,450.50")

        // Another window deletes the larger Groceries expense; the report's list isn't on screen to hear it.
        fake.snapshot.transactions = fake.snapshot.transactions.map { transaction in
            guard transaction.id == deleted.id else {
                return transaction
            }
            var gone = transaction
            gone.deletedAt = S.date(10, 25)
            return gone
        }
        drill.refresh(at: 1)

        let after = try #require(drill.drillDown)
        #expect(after.entries.count == 1)
        #expect(after.amountText == "₹450.50")
        #expect(after.countText == "1 transaction")
        #expect(after.caption.hasPrefix("1.8% of spending"))
        #expect(report.totalText == "₹25,450.50")
        #expect(report.rows.first { $0.categoryID == S.groceries.id }?.amountText == "₹450.50")
        #expect(drill.loadFailed == false)
    }

    @Test("One store change is read once, whether the report or its drill-down hears it first")
    func oneReadPerChange() throws {
        let fake = FakeSpendingReportUseCase(snapshot: S.snapshot([S.expense("2000", S.groceries, 10, 3)]))
        let report = S.model(fake)
        report.load(at: 4)
        let drill = report.makeDrillDown(for: try #require(report.rows.first))
        drill.refresh(at: 5)
        report.load(at: 5)
        drill.refresh(at: 5)
        #expect(fake.requests.count == 2)
        #expect(drill.drillDown?.entries.count == 1)
    }

    @Test("A failed read after a change shows the load failure")
    func refreshFailure() throws {
        let fake = FakeSpendingReportUseCase(snapshot: S.snapshot([S.expense("2000", S.groceries, 10, 3)]))
        let report = S.model(fake)
        report.load(at: 0)
        let drill = report.makeDrillDown(for: try #require(report.rows.first))
        drill.load()
        fake.fails = true
        drill.refresh(at: 1)
        #expect(drill.drillDown == nil)
        #expect(drill.loadFailed)
    }
}

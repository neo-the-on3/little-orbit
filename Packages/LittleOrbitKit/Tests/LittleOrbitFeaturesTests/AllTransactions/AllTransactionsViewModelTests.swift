import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

@MainActor
@Suite("All Transactions view model (#243, D421)")
struct AllTransactionsViewModelTests {
    typealias F = AllTransactionsFixture  // swiftlint:disable:this type_name

    @Test("Checks 1–3: newest first under day headers, own currency, hidden accounts listed, no balance")
    func listsEveryAccount() async throws {
        let model = await F.model(F.useCases(try F.repository()))
        #expect(
            model.sections.map(\.title) == [
                "Today · Wed, 28 Oct", "Yesterday · Tue, 27 Oct", "Mon, 26 Oct", "Sun, 25 Oct",
            ]
        )
        let rows = model.allRows
        #expect(rows.map(\.id) == [F.metro.id, F.bakery.id, F.tea.id, F.move.id])
        #expect(rows.map(\.row.accountText) == ["Euro Card", "Everyday Checking", "Old Wallet", "Everyday Checking"])
        #expect(rows.map(\.accountID) == [F.euroID, F.checkingID, F.walletID, F.checkingID])
        #expect(rows.map(\.row.amountText) == ["−€12.50", "−$8.40", "−₹60.00", "−$100.00"])
        #expect(rows.allSatisfy { $0.row.balanceValueText.isEmpty && !$0.row.accessibilityLabel.contains("balance") })
    }

    @Test("Description and Payee cells follow D326.2: payee only in Payee, the fallback in Description")
    func descriptionAndPayee() async throws {
        let rows = await F.model(F.useCases(try F.repository())).allRows
        let bakery = try #require(rows.first { $0.id == F.bakery.id })
        #expect(bakery.payee == "Corner Bakery")
        #expect(bakery.descriptionText == "Expense")
        #expect(bakery.isDescriptionFallback)
        let metro = try #require(rows.first { $0.id == F.metro.id })
        #expect(metro.descriptionText == "Metro Ticket")
        #expect(metro.payee.isEmpty)
        #expect(!metro.isDescriptionFallback)
        let move = try #require(rows.first { $0.id == F.move.id })
        #expect(move.descriptionText == "To Holiday Savings")
    }

    @Test("Check 6: a transfer is listed once, under its source account (D25)")
    func transferOnce() async throws {
        let rows = await F.model(F.useCases(try F.repository())).allRows
        #expect(rows.filter { $0.id == F.move.id }.count == 1)
        #expect(rows.first { $0.id == F.move.id }?.accountID == F.checkingID)
    }

    @Test("Check 10: a hand-entered future row is Upcoming; an unrecorded scheduled one isn't listed (D425.3)")
    func upcomingStoredOnly() async throws {
        let concert = F.transaction(
            .expense,
            60,
            on: F.date(12, 2),
            account: F.checkingID,
            details: "Concert Tickets",
        )
        let model = await F.model(F.useCases(try F.repository([F.bakery, concert])))
        let upcoming = try #require(model.sections.first)
        #expect(upcoming.kind == .upcoming)
        #expect(upcoming.rows.map(\.id) == [concert.id])
        #expect(upcoming.rows.first?.isUpcoming == true)
        #expect(model.allRows.count == 2)
    }

    @Test("Check 9: no transactions shows the empty state with D320.5's copy (D425.1)")
    func emptyState() async throws {
        let model = await F.model(F.useCases(try F.repository([])))
        #expect(model.hasLoaded)
        #expect(model.isEmpty)
        #expect(model.emptyTitle == "No Transactions")
        #expect(model.emptyMessage == "Transactions you add will appear here.")
        #expect(!model.emptyMessage.contains("for this account"))
    }

    @Test("Check 7: opening one row edits it; several open Bulk Edit in table order; the summary counts them")
    func editTargets() async throws {
        let model = await F.model(F.useCases(try F.repository()))
        #expect(model.editTarget(for: [F.metro.id]) == .transaction(F.metro.id))
        #expect(model.editTarget(for: [F.tea.id, F.metro.id]) == .bulkEdit([F.metro.id, F.tea.id]))
        #expect(model.editTarget(for: [UUID()]) == nil)
        model.selection = [F.metro.id, F.bakery.id]
        #expect(model.selectionSummary == "2 selected")
    }

    @Test("The list follows the store: a change made elsewhere shows on the next load, and the selection keeps rows")
    func reloadKeepsSelection() async throws {
        let repository = try F.repository()
        let useCases = F.useCases(repository)
        let model = await F.model(useCases)
        model.selection = [F.metro.id, F.tea.id]
        _ = try useCases.changes.remove(ids: [F.tea.id])
        await model.load()
        #expect(!model.visibleIDs.contains(F.tea.id))
        #expect(model.selection == [F.metro.id])
    }
}

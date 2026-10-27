import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// N5 on #286: one notification per change, with what it touched, so a window whose account it didn't touch
/// skips its reload, and one that needs it reloads once, keeping its selection.
@MainActor
@Suite("Ledger changes: what each one touched")
struct LedgerDeltaTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @Test("A window up to date sees nothing; one behind sees each change since, merged")
    func since() {
        let updates = LedgerUpdates()
        let first = UUID()
        let second = UUID()
        #expect(updates.delta(since: 0) == .nothing)
        updates.changed(LedgerDelta(accountIDs: [first], transactionIDs: [first]))
        updates.changed(LedgerDelta(accountIDs: [second]))
        #expect(updates.revision == 2)
        #expect(updates.delta(since: 2) == .nothing)
        #expect(updates.delta(since: 1) == LedgerDelta(accountIDs: [second]))
        #expect(updates.delta(since: 0) == LedgerDelta(accountIDs: [first, second], transactionIDs: [first]))
        #expect(!updates.delta(since: 0).affects(account: UUID()))
        #expect(updates.delta(since: 0).affects(account: second))
    }

    @Test("A change without what it touched, a restore, or one further back than the kept history is everything")
    func everything() {
        let updates = LedgerUpdates()
        updates.changed(LedgerDelta(accountIDs: [UUID()]))
        updates.changed()
        #expect(updates.delta(since: 1) == .everything)
        updates.ledgerReplaced()
        #expect(updates.delta(since: 2) == .everything)
        for _ in 0..<40 {
            updates.changed(LedgerDelta(accountIDs: [UUID()]))
        }
        #expect(updates.delta(since: 3) == .everything, "Behind the kept history")
        #expect(updates.delta(since: updates.revision - 1) != .everything)
        #expect(LedgerDelta.everything.affects(account: UUID()))
    }

    @Test("A transaction change touches its accounts; an account change or unread accounts touch everything")
    func ofChange() {
        let row = F.expense(10, on: F.now, account: F.cardID)
        #expect(
            LedgerDelta(.replaced([row]), accountIDs: [F.cardID])
                == LedgerDelta(accountIDs: [F.cardID], transactionIDs: [row.id])
        )
        #expect(LedgerDelta(.createdPayees([], .added([row.id])), accountIDs: [F.cardID]).transactionIDs == [row.id])
        #expect(LedgerDelta(.replaced([row]), accountIDs: nil) == .everything)
        #expect(LedgerDelta(.addedAccount(F.cardID), accountIDs: [F.cardID]) == .everything)
    }

    @Test("An edit in one window: the other account's register skips; the edited one reloads once, keeping selection")
    func windows() async throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 19), account: F.cardID, details: "Lunch")
        let rent = F.expense(9_000, on: F.date(2026, 10, 18), details: "Rent")
        let repository = try F.repository([lunch, rent])
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let updates = LedgerUpdates()
        let window = TestWindow(useCases, updates: updates)
        func register(_ account: UUID) -> AccountHistoryViewModel {
            let model = AccountHistoryViewModel(
                useCases: useCases,
                accountID: account,
                locale: F.india,
                timeZone: F.zone,
                now: { F.now },
            )
            model.seenRevision = updates.revision
            model.load()
            return model
        }
        let card = register(F.cardID)
        let savings = register(F.savingsID)
        card.selection = [lunch.id]
        savings.selection = [rent.id]
        let savingsSections = savings.sections

        var edited = lunch
        edited.details = "Team lunch"
        window.history.record(try useCases.saveTransactions.save([edited]))
        // Something the savings window would show, written behind its back: it must not reload for the card edit.
        var moved = rent
        moved.amount = 9_500
        try repository.saveTransaction(moved)

        await card.refresh(after: updates)
        await savings.refresh(after: updates)
        #expect(card.sections.flatMap(\.rows).map(\.title).contains("Team lunch"))
        #expect(card.selection == [lunch.id], "Selection kept")
        #expect(savings.sections == savingsSections, "Not touched: no reload")
        #expect(savings.selection == [rent.id])
        #expect(card.seenRevision == updates.revision && savings.seenRevision == updates.revision)

        // A change that may touch anything reloads every register.
        updates.changed()
        await savings.refresh(after: updates)
        #expect(savings.sections != savingsSections)
    }

    @Test("A Bulk Edit Undo notifies once, for the accounts its rows are in")
    func batchUndo() async throws {
        let rows = BulkEditBatchTests.rows(6)
        let disk = FullDiskLedgerRepository(try F.repository(rows))
        disk.hasBatchPath = true
        let useCases = TransactionUseCases(repository: disk, categoryNames: CatalogDefaultCategoryNames())
        let updates = LedgerUpdates()
        let window = TestWindow(useCases, updates: updates)
        let request = BulkEditBatchTests.request(rows, accounts: try disk.accounts())
        let change = try await useCases.bulkEdit.apply(request, reporting: .silent)
        window.history.record(change)
        window.history.markBulkEdit(change)
        let recorded = updates.revision
        window.history.undo()
        await window.history.batchRun?.task.value
        #expect(updates.revision == recorded + 1, "One notification")
        let delta = updates.delta(since: recorded)
        #expect(!delta.isEverything)
        #expect(delta.accountIDs == [F.savingsID])
        #expect(delta.transactionIDs == Set(rows.map(\.id)))
    }
}

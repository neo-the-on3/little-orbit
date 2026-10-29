import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #341 (review 5692037397): All Transactions loads and refreshes off the main thread, through `LedgerUpdates`,
/// rebuilding only the rows a change touched, and a delete updates it once. Made-up data.
@MainActor
@Suite("All Transactions refreshes in place, off the main thread (#341)", .timeLimit(.minutes(1)))
struct AllTransactionsRefreshTests {
    typealias F = AllTransactionsFixture  // swiftlint:disable:this type_name

    /// A registered list over the fixture ledger, with the window that records its changes.
    struct Setup {
        let repository: InMemoryLedgerRepository
        let useCases: TransactionUseCases
        let updates: LedgerUpdates
        let model: AllTransactionsViewModel
        let window: TestWindow
    }

    static func setup(_ transactions: [Transaction] = [F.bakery, F.metro, F.tea, F.move]) async throws -> Setup {
        let repository = try F.repository(transactions)
        let useCases = F.useCases(repository)
        let updates = LedgerUpdates()
        let model = await F.model(useCases, updates: updates)
        return Setup(
            repository: repository,
            useCases: useCases,
            updates: updates,
            model: model,
            window: TestWindow(useCases, updates: updates),
        )
    }

    /// Edits Metro Ticket's amount in the register's form and records it, as the editor sheet does.
    static func editMetro(_ setup: Setup, to amount: String) throws {
        let form = TransactionFormViewModel(
            useCases: setup.useCases,
            mode: .edit(F.metro.id),
            locale: F.locale,
            timeZone: F.zone,
        )
        form.expressionInput = amount
        let change = try #require(form.save())
        setup.window.history.record(change)
    }

    /// What a fresh full load of the same store shows.
    static func fullLoad(_ setup: Setup) async -> [AllTransactionsSection] {
        await F.model(setup.useCases).sections
    }

    @Test("Criterion 1: the launch load reads on the main actor and builds every row off the main actor")
    func launchOffMain() async throws {
        let setup = try await Self.setup()
        let stats = try #require(setup.model.content?.stats)
        #expect(!stats.ranOnMainActor, "Built on a detached task")
        #expect(stats.isFull)
        #expect(stats.rowsBuilt == 4)
        #expect(setup.model.allRows.count == 4)
        // The check itself works: the same build, called here on the main actor, says so.
        let input = AllTransactionsBuildInput(
            ledger: try setup.useCases.loadLedger.ledger(),
            previous: nil,
            delta: .everything,
            formatter: MoneyFormatter(locale: F.locale),
            text: TransactionText(locale: F.locale),
            today: TransactionTiming.today(F.now, timeZone: F.zone),
        )
        #expect(input.build().stats.ranOnMainActor)
    }

    @Test("Criteria 1–2: an edit starts one refresh as it's posted, off the main thread, rebuilding only its row")
    func editRebuildsOneRow() async throws {
        let setup = try await Self.setup()
        let model = setup.model
        #expect(model.recomputes == 1)
        try Self.editMetro(setup, to: "14")
        #expect(setup.updates.refreshesRunning == 1, "The change started and counted the refresh as it was posted")
        await F.settled(model, setup.updates)
        #expect(model.recomputes == 2)
        let stats = try #require(model.content?.stats)
        #expect(!stats.isFull)
        #expect(stats.rowsBuilt == 1)
        #expect(!stats.ranOnMainActor)
        #expect(model.allRows.first { $0.id == F.metro.id }?.row.amountText == "−€14.00")
        #expect(model.sections == (await Self.fullLoad(setup)))

        // The view's `onChange(of: revision)` for the same change finds it up to date.
        await model.refresh(after: setup.updates)
        #expect(model.recomputes == 2, "No second refresh")
    }

    @Test("Criterion 4: deleting one row updates the list once, with no load of its own")
    func oneUpdatePerDelete() async throws {
        let setup = try await Self.setup()
        let model = setup.model
        let change = try #require(model.requestDelete(ids: [F.bakery.id]))
        #expect(model.recomputes == 1, "remove(_:) doesn't load")
        setup.window.history.record(change)
        await F.settled(model, setup.updates)
        await model.refresh(after: setup.updates)
        #expect(model.recomputes == 2, "One update for the delete")
        #expect(model.content?.stats.rowsBuilt == 0, "Nothing to build: a row only went")
        #expect(!model.visibleIDs.contains(F.bakery.id))
        #expect(model.sections == (await Self.fullLoad(setup)))
    }

    @Test("Criterion 4: confirming a bulk delete updates the list once")
    func oneUpdatePerBulkDelete() async throws {
        let setup = try await Self.setup()
        let model = setup.model
        model.requestDelete(ids: [F.bakery.id, F.tea.id])
        let change = try #require(model.confirmDelete())
        #expect(model.recomputes == 1, "confirmDelete() doesn't load")
        setup.window.history.record(change)
        await F.settled(model, setup.updates)
        await model.refresh(after: setup.updates)
        #expect(model.recomputes == 2, "One update for the bulk delete")
        #expect(model.visibleIDs == [F.metro.id, F.move.id])
    }

    @Test("Criterion 2: adds, moves to another day or to Upcoming, and deletes each match a full rebuild")
    func matchesFullRebuild() async throws {
        let setup = try await Self.setup()
        let model = setup.model
        let added = F.transaction(.income, 40, on: F.date(10, 27, 9), account: F.walletID, details: "Refund")
        try setup.repository.saveTransaction(added)
        setup.updates.changed(LedgerDelta(accountIDs: [F.walletID], transactionIDs: [added.id]))
        await F.settled(model, setup.updates)
        #expect(model.sections == (await Self.fullLoad(setup)))
        #expect(model.content?.stats.rowsBuilt == 1)

        var moved = try #require(try setup.repository.transactions().first { $0.id == F.tea.id })
        moved.date = F.date(12, 2)
        try setup.repository.updateTransaction(moved)
        setup.updates.changed(LedgerDelta(accountIDs: [F.walletID], transactionIDs: [moved.id]))
        await F.settled(model, setup.updates)
        #expect(model.sections.first?.kind == .upcoming)
        #expect(model.sections == (await Self.fullLoad(setup)))

        try setup.repository.deleteTransaction(id: F.metro.id)
        setup.updates.changed(LedgerDelta(accountIDs: [F.euroID], transactionIDs: [F.metro.id]))
        await F.settled(model, setup.updates)
        #expect(model.sections == (await Self.fullLoad(setup)))
        #expect(model.recomputes == 4)
    }

    @Test("A change to anything but transactions, such as a payee rename, rebuilds every row")
    func otherChangesRebuildAll() async throws {
        let setup = try await Self.setup()
        try setup.repository.savePayee(Payee(id: F.bakeryPayeeID, name: "Corner Bakery & Café"))
        setup.updates.changed()
        await F.settled(setup.model, setup.updates)
        #expect(setup.model.content?.stats.isFull == true)
        #expect(setup.model.content?.stats.rowsBuilt == 4)
        #expect(setup.model.allRows.first { $0.id == F.bakery.id }?.payee == "Corner Bakery & Café")
    }

    @Test("Criteria 2 and 6: 10,000 made-up rows, one edit builds one row and matches a full rebuild")
    func tenThousandRows() async throws {
        let accounts = [F.checkingID, F.euroID, F.walletID, F.holidayID]
        let rows = (0..<10_000)
            .map { index in
                F.transaction(
                    .expense,
                    Decimal(index % 90 + 1),
                    on: F.date(1 + index % 10, 1 + index % 28, index % 24),
                    account: accounts[index % 4],
                    details: "Item \(index)",
                )
            }
        let repository = try F.repository([])
        try repository.saveNewTransactions(rows)
        let useCases = F.useCases(repository)
        let updates = LedgerUpdates()
        let model = await F.model(useCases, updates: updates)
        #expect(model.allRows.count == 10_000)
        var edited = rows[4_321]
        edited.amount = 7
        edited.date = F.date(10, 28, 7)
        try repository.updateTransaction(edited)
        updates.changed(LedgerDelta(accountIDs: [edited.accountID!], transactionIDs: [edited.id]))
        await F.settled(model, updates)
        #expect(model.content?.stats.rowsBuilt == 1)
        #expect(model.content?.stats.ranOnMainActor == false)
        #expect(model.sections == (await F.model(useCases)).sections)
    }

    @Test("A slower build that finishes after a newer one is dropped, and the newer one shows both changes")
    func olderBuildDropped() async throws {
        let setup = try await Self.setup()
        let model = setup.model
        let held = HeldBuild()
        model.buildContent = held.builder
        try Self.editMetro(setup, to: "14")
        await RealTime.eventually { held.waiting == 1 }
        try #require(held.waiting == 1, "The first refresh is building")
        #expect(setup.updates.refreshesRunning == 1, "A batch would wait for it")
        model.buildContent = AllTransactionsContent.offMain
        try Self.editMetro(setup, to: "15")
        await RealTime.eventually { model.shownRevision == setup.updates.revision }
        held.finish()
        await RealTime.eventually { setup.updates.refreshesRunning == 0 }
        #expect(model.allRows.first { $0.id == F.metro.id }?.row.amountText == "−€15.00")
        #expect(model.sections == (await Self.fullLoad(setup)))
    }
}

/// Holds the builds started through `builder` until `finish()`, then lets them run.
@MainActor
private final class HeldBuild {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    var waiting: Int { continuations.count }

    nonisolated var builder: AllTransactionsContentBuilder {
        { input in
            await self.hold()
            return input.build(isolation: nil)
        }
    }

    private func hold() async {
        await withCheckedContinuation { continuations.append($0) }
    }

    func finish() {
        let held = continuations
        continuations = []
        for continuation in held {
            continuation.resume()
        }
    }
}

import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D421 merge gate (D285.5): no edit or delete from All Transactions touches a transaction in another account,
/// and one Undo restores exactly what was there, both legs of a transfer included (checks 4–6).
@MainActor
@Suite("All Transactions: edits, deletes and Undo stay in their own account (#243 gate)")
struct AllTransactionsUndoTests {
    typealias F = AllTransactionsFixture  // swiftlint:disable:this type_name

    @Test("Check 4: editing Metro Ticket to €14.00 changes only Euro Card, and one Undo restores −€12.50 exactly")
    func editOnlyItsAccount() throws {
        let repository = try F.repository()
        let useCases = F.useCases(repository)
        let model = F.model(useCases)
        let before = try F.stored(repository)
        let balances = try F.balances(repository)
        guard case .transaction(let id) = model.editTarget(for: [F.metro.id]) else {
            Issue.record("Metro Ticket opens the editor")
            return
        }
        let form = TransactionFormViewModel(useCases: useCases, mode: .edit(id), locale: F.locale, timeZone: F.zone)
        #expect(form.accountID == F.euroID)
        form.expressionInput = "14"
        let change = try #require(form.save())
        let window = TestWindow(useCases)
        window.history.record(change)
        model.load()

        let after = try F.stored(repository)
        #expect(after.first { $0.id == F.metro.id }?.amount == 14)
        #expect(after.first { $0.id == F.metro.id }?.accountID == F.euroID)
        #expect(after.filter { $0.id != F.metro.id } == before.filter { $0.id != F.metro.id })
        let changed = try F.balances(repository)
        #expect(changed[1] == -14)
        #expect([changed[0], changed[2], changed[3]] == [balances[0], balances[2], balances[3]])
        #expect(model.allRows.first { $0.id == F.metro.id }?.row.amountText == "−€14.00")

        window.history.undo()
        model.load()
        #expect(try F.stored(repository) == before)
        #expect(try F.balances(repository) == balances)
        #expect(model.allRows.first { $0.id == F.metro.id }?.row.amountText == "−€12.50")
    }

    @Test("Check 5: deleting Corner Bakery removes it from every list, and one Undo brings it back exactly")
    func deleteAndUndo() throws {
        let repository = try F.repository()
        let useCases = F.useCases(repository)
        let model = F.model(useCases)
        let before = try F.stored(repository)
        let balances = try F.balances(repository)
        model.selection = [F.bakery.id]
        let change = try #require(model.requestDelete(ids: model.selection))
        let window = TestWindow(useCases)
        window.history.record(change)

        #expect(!model.visibleIDs.contains(F.bakery.id))
        #expect(model.selection.isEmpty)
        #expect(try F.stored(repository) == before.filter { $0.id != F.bakery.id })
        let deleted = try F.balances(repository)
        #expect(deleted[0] == balances[0].map { $0 + Decimal(string: "8.40")! })
        #expect([deleted[1], deleted[2], deleted[3]] == [balances[1], balances[2], balances[3]])

        window.history.undo()
        model.load()
        let restored = try #require(try F.stored(repository).first { $0.id == F.bakery.id })
        #expect(restored == before.first { $0.id == F.bakery.id })
        #expect(try F.stored(repository) == before)
        #expect(try F.balances(repository) == balances)
        #expect(model.allRows.first { $0.id == F.bakery.id }?.accountID == F.checkingID)
    }

    @Test("Check 6: deleting the transfer and Undo remove and restore both legs, both balances exact")
    func transferDeleteAndUndo() throws {
        let repository = try F.repository()
        let useCases = F.useCases(repository)
        let model = F.model(useCases)
        let before = try F.stored(repository)
        let balances = try F.balances(repository)
        let change = try #require(model.requestDelete(ids: [F.move.id]))
        let window = TestWindow(useCases)
        window.history.record(change)
        let deleted = try F.balances(repository)
        #expect(deleted[0] == balances[0].map { $0 + 100 })
        #expect(deleted[3] == balances[3].map { $0 - 100 })
        #expect(deleted[1] == balances[1] && deleted[2] == balances[2])

        window.history.undo()
        model.load()
        #expect(try F.stored(repository) == before)
        #expect(try F.balances(repository) == balances)
        #expect(model.allRows.filter { $0.id == F.move.id }.count == 1)
    }

    @Test("Check 7: several rows across accounts ask first, then delete as one step that one Undo restores")
    func bulkDeleteAcrossAccounts() throws {
        let repository = try F.repository()
        let useCases = F.useCases(repository)
        let model = F.model(useCases)
        let before = try F.stored(repository)
        #expect(model.requestDelete(ids: [F.bakery.id, F.metro.id]) == nil, "Nothing is deleted before confirming")
        let prompt = try #require(model.deletePrompt)
        #expect(prompt.ids == [F.metro.id, F.bakery.id])
        #expect(try F.stored(repository) == before)
        let change = try #require(model.confirmDelete())
        let window = TestWindow(useCases)
        window.history.record(change)
        #expect(model.visibleIDs == [F.tea.id, F.move.id])
        #expect(window.history.undoTitle?.hasPrefix("Delete 2 Transactions") == true)

        window.history.undo()
        #expect(try F.stored(repository) == before)
        model.cancelDelete()
        #expect(model.deletePrompt == nil)
    }
}

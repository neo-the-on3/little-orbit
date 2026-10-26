import Foundation
import LittleOrbitDomain
import Testing

/// Saving the Scheduled form with its pending payee, and the save's Undo and Redo (#197, D350.1, D351, D352):
/// the payee is stored with the item in one save, one Undo takes both back, and there's never a duplicate payee.
@MainActor
@Suite("Scheduled form save and its Undo (#197)")
struct ScheduledItemSaveTests {
    private typealias Fix = ScheduledFixture
    private static let oldShopID = UUID(uuidString: "5C000000-0000-4000-8000-0000000000A1")!

    private static func repository() -> FakeScheduleRepository {
        var ledger = Fix.ledger
        ledger.payees.append(Payee(id: oldShopID, name: "Old Shop", isArchived: true, createdAt: Fix.created))
        return FakeScheduleRepository(ledger)
    }

    private static var rent: ScheduledItem {
        Fix.rent(start: Fix.day(2026, 11, 1), automatic: false)
    }

    @Test("Create “‹name›” stores the payee, trimmed, with the item in one save")
    func createsPayeeOnSave() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .create("  Gym Co  "))
        let created = try #require(change.createdPayee)
        #expect(created.name == "Gym Co")
        #expect(repository.snapshot.payees.filter { $0.name == "Gym Co" }.count == 1)
        #expect(repository.snapshot.scheduledItems.first?.payeeID == created.id)
        #expect(change.isNew)
        #expect(repository.saves == 1)
    }

    @Test("A name that's now a payee's, in any case, uses that payee and creates none")
    func reusesExisting() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .create("corner bakery"))
        #expect(change.createdPayee == nil)
        #expect(change.after.payeeID == Fix.bakeryID)
        #expect(repository.snapshot.payees.count == 2)
    }

    @Test("D351.1: one Undo removes the new item and its new payee; Redo restores both")
    func undoAndRedoNewItemWithPayee() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .create("Gym Co"))
        guard case .reverted(let undone) = try repository.revertScheduledItemSave(change, undone: false) else {
            Issue.record("Undo was stale")
            return
        }
        #expect(repository.snapshot.scheduledItems.isEmpty)
        #expect(!repository.snapshot.payees.contains { $0.name == "Gym Co" && $0.deletedAt == nil })
        guard case .reverted = try repository.revertScheduledItemSave(undone, undone: true) else {
            Issue.record("Redo was stale")
            return
        }
        let gym = repository.snapshot.payees.filter { $0.name == "Gym Co" && $0.deletedAt == nil }
        #expect(gym.count == 1)
        #expect(repository.snapshot.scheduledItems.first?.payeeID == gym.first?.id)
    }

    @Test("D351.2: Use archived unarchives the payee on Save; one Undo removes the item and archives it again")
    func unarchiveAndUndo() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .unarchive(Self.oldShopID))
        #expect(change.unarchivedPayee?.id == Self.oldShopID)
        #expect(repository.snapshot.payees.first { $0.id == Self.oldShopID }?.isArchived == false)
        #expect(change.after.payeeID == Self.oldShopID)
        guard case .reverted(let undone) = try repository.revertScheduledItemSave(change, undone: false) else {
            Issue.record("Undo was stale")
            return
        }
        #expect(repository.snapshot.scheduledItems.isEmpty)
        #expect(repository.snapshot.payees.first { $0.id == Self.oldShopID }?.isArchived == true)
        _ = try repository.revertScheduledItemSave(undone, undone: true)
        #expect(repository.snapshot.payees.first { $0.id == Self.oldShopID }?.isArchived == false)
        #expect(repository.snapshot.scheduledItems.first?.payeeID == Self.oldShopID)
    }

    @Test("D351.2: an archived payee's name is never created twice")
    func noDuplicateOfArchived() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .create(" old shop "))
        #expect(change.createdPayee == nil)
        #expect(change.after.payeeID == Self.oldShopID)
        #expect(repository.snapshot.payees.filter { $0.name.lowercased() == "old shop" }.count == 1)
    }

    @Test("D352.2: Undo is stale once an occurrence has been recorded since the save, and writes nothing")
    func staleAfterRecordedOccurrence() throws {
        let repository = Self.repository()
        let useCases = repository.useCases()
        let change = try useCases.save(Self.rent, payee: .create("Gym Co"))
        repository.now = Fix.date(2026, 11, 1)
        _ = try useCases.payNow(itemID: change.itemID, occurrence: Fix.day(2026, 11, 1))
        let before = repository.snapshot
        let result = try repository.revertScheduledItemSave(change, undone: false)
        #expect(result == .stale(.scheduledItemChanged(change.itemID)))
        #expect(repository.snapshot == before)
    }

    @Test("D352.2: Undo with nothing recorded since takes the save back cleanly")
    func cleanUndo() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: nil)
        #expect(try repository.revertScheduledItemSave(change, undone: false) == .reverted(change))
        #expect(repository.snapshot.scheduledItems.isEmpty)
    }

    @Test("D340.9: Undo of an edit puts the item back as it was")
    func undoEdit() throws {
        let repository = Self.repository()
        let useCases = repository.useCases()
        let first = try useCases.save(Self.rent, payee: nil)
        var edited = first.after
        edited.amount = 30_000
        let change = try useCases.save(edited, payee: nil)
        #expect(!change.isNew)
        #expect(change.before == first.after)
        _ = try repository.revertScheduledItemSave(change, undone: false)
        #expect(repository.snapshot.scheduledItems.first?.amount == 25_000)
    }
}

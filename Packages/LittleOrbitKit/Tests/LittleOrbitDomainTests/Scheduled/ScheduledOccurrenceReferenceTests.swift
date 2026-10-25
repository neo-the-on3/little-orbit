import Foundation
import LittleOrbitDomain
import Testing

/// An occurrence's own category or payee that's deleted or merged away (Tech Architect B2 on #202), and NB 1 and
/// NB 2 of that review. Made-up data.
extension ScheduledOccurrenceEditTests {
    private static let foodID = UUID(uuidString: "5C000000-0000-4000-8000-0000000000F1")!
    private static let groceriesID = UUID(uuidString: "5C000000-0000-4000-8000-0000000000F2")!
    private static let cafeID = UUID(uuidString: "5C000000-0000-4000-8000-0000000000F3")!
    private var december: CalendarDay { Fix.day(2026, 12, 1) }

    /// Rent from 1 Aug, with Food, Groceries and Cafe in the ledger; today is 20 Nov, Aug to Nov recorded.
    private func rentScene(automatic: Bool) throws -> (repository: FakeScheduleRepository, id: UUID) {
        let rent = Fix.rent(automatic: automatic)
        let repository = try scene(rent, today: Fix.day(2026, 11, 20))
        repository.snapshot.categories += [
            TransactionCategory(id: Self.foodID, name: "Food", kind: .expense, createdAt: Fix.created),
            TransactionCategory(id: Self.groceriesID, name: "Groceries", kind: .expense, createdAt: Fix.created),
        ]
        repository.snapshot.payees.append(Payee(id: Self.cafeID, name: "Cafe", createdAt: Fix.created))
        for month in 8...11 {
            try repository.useCases().payNow(itemID: rent.id, occurrence: Fix.day(2026, month, 1))
        }
        return (repository, rent.id)
    }

    private func restored(_ snapshot: LedgerSnapshot) throws -> LedgerSnapshot {
        let manifest = BackupManifest(
            kind: .automatic,
            createdAt: Fix.created,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: snapshot.accounts.count,
            transactionCount: snapshot.transactions.count,
            attachmentCount: 0,
        )
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let decoded = try codec.decode(try codec.encode(BackupContents(manifest: manifest, ledger: snapshot)))
        try LedgerBook.validateStoredScheduledItems(in: decoded.ledger)
        return decoded.ledger
    }

    @Test("B2: 1 Dec alone on Food, Food deleted: catch-up records Dec to Feb on Housing; a backup restores")
    func deletedEditCategoryCatchesUp() throws {
        let (repository, id) = try rentScene(automatic: true)
        try edit(id, in: repository, occurrence: december, scope: .thisOccurrence) { $0.categoryID = Self.foodID }
        let food = try #require(repository.snapshot.categories.first { $0.id == Self.foodID })
        repository.snapshot = try LedgerBook.deletingCategory(
            id: Self.foodID,
            reassigningTo: nil,
            in: repository.snapshot,
            now: repository.now,
        )
        let backup = try restored(repository.snapshot)
        #expect(backup.scheduledItems[0].edit(for: december) == nil)
        // Food back with the same ID gives 1 Dec its own category again; the stored value was kept.
        var undone = repository.snapshot
        undone.categories.append(food)
        let back = try #require(LedgerBook.activeScheduledItems(in: undone).first)
        #expect(back.resolved(for: december).categoryID == Self.foodID)
        repository.now = Fix.date(2027, 2, 2)
        let result = try repository.useCases().catchUp(atLaunch: true)
        #expect(result.failedItemIDs.isEmpty)
        #expect(result.posted.count == 3)
        #expect(result.posted.allSatisfy { $0.categoryID == Fix.housingID })
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
    }

    @Test("B2: Food deleted and reassigned to Groceries: 1 Dec's own category becomes Groceries")
    func reassignedEditCategory() throws {
        let (repository, id) = try rentScene(automatic: true)
        try edit(id, in: repository, occurrence: december, scope: .thisOccurrence) { $0.categoryID = Self.foodID }
        repository.snapshot = try LedgerBook.deletingCategory(
            id: Self.foodID,
            reassigningTo: Self.groceriesID,
            in: repository.snapshot,
            now: repository.now,
        )
        #expect(try stored(id, repository).edit(for: december)?.categoryID == Self.groceriesID)
        repository.now = Fix.date(2026, 12, 2)
        let result = try repository.useCases().catchUp(atLaunch: true)
        #expect(result.failedItemIDs.isEmpty)
        #expect(result.posted.map(\.categoryID) == [Self.groceriesID])
        let backup = try restored(repository.snapshot)
        #expect(backup.scheduledItems[0].occurrence(on: december)?.edit?.categoryID == Self.groceriesID)
    }

    @Test("B2: 1 Dec alone with payee Cafe, Cafe deleted: Pay Now records once with the item's payee")
    func deletedEditPayee() throws {
        let (repository, id) = try rentScene(automatic: false)
        try edit(id, in: repository, occurrence: december, scope: .thisOccurrence) { $0.payeeID = Self.cafeID }
        let cafe = try #require(repository.snapshot.payees.first { $0.id == Self.cafeID })
        repository.snapshot = try LedgerBook.deletingPayee(
            id: Self.cafeID,
            in: repository.snapshot,
            now: repository.now,
        )
        let backup = try restored(repository.snapshot)
        #expect(backup.scheduledItems[0].edit(for: december) == nil)
        var undone = repository.snapshot
        undone.payees.append(cafe)
        let back = try #require(LedgerBook.activeScheduledItems(in: undone).first)
        #expect(back.resolved(for: december).payeeID == Self.cafeID)
        repository.now = Fix.date(2026, 12, 1)
        let paid = try #require(try repository.useCases().payNow(itemID: id, occurrence: december))
        #expect(paid.payeeID == nil)
        #expect(try repository.useCases().payNow(itemID: id, occurrence: december) == nil)
    }

    @Test("B2: Cafe merged into Corner Bakery: 1 Dec's own payee becomes Corner Bakery, and Pay Now records it")
    func mergedEditPayee() throws {
        let (repository, id) = try rentScene(automatic: false)
        try edit(id, in: repository, occurrence: december, scope: .thisOccurrence) { $0.payeeID = Self.cafeID }
        repository.snapshot = try LedgerBook.mergingPayees(
            Self.cafeID,
            into: Fix.bakeryID,
            in: repository.snapshot,
            now: repository.now,
        )
        #expect(try stored(id, repository).edit(for: december)?.payeeID == Fix.bakeryID)
        let backup = try restored(repository.snapshot)
        #expect(backup.scheduledItems[0].edit(for: december)?.payeeID == Fix.bakeryID)
        repository.now = Fix.date(2026, 12, 1)
        let paid = try #require(try repository.useCases().payNow(itemID: id, occurrence: december))
        #expect(paid.payeeID == Fix.bakeryID)
    }

    @Test("NB 1: Never from the 20 Sep form keeps 20 Aug's own ₹651, so the one-off pays ₹651")
    func neverFromLaterOccurrenceKeepsStartValues() throws {
        var phone = Fix.rent(amount: 700, start: Fix.day(2026, 8, 20), automatic: false)
        phone.accountID = Fix.fundID
        let repository = try scene(phone, today: Fix.day(2026, 8, 10))
        try edit(phone.id, in: repository, occurrence: Fix.day(2026, 8, 20), scope: .thisOccurrence) {
            $0.amount = 651
        }
        try edit(phone.id, in: repository, occurrence: Fix.day(2026, 9, 20), scope: .allFuture) {
            $0.repeatRule = .never
            $0.details = "Phone Plan"
        }
        let item = try stored(phone.id, repository)
        #expect(item.amount == 651)
        #expect(item.accountID == Fix.fundID)
        #expect(item.details == "Phone Plan")
        repository.now = Fix.date(2026, 8, 20)
        let paid = try #require(try repository.useCases().payNow(itemID: phone.id, occurrence: Fix.day(2026, 8, 20)))
        #expect(paid.amount == 651)
    }

    @Test("NB 2: saving 1 Dec or 1 Jan while 1 Dec's own account is deleted keeps it for Undo Delete Account")
    func saveKeepsStoredAccount() throws {
        let (repository, id) = try rentScene(automatic: false)
        try edit(id, in: repository, occurrence: december, scope: .thisOccurrence) { $0.accountID = Fix.fundID }
        let fund = try #require(repository.snapshot.accounts.first { $0.id == Fix.fundID })
        repository.snapshot = try LedgerBook.deletingAccount(
            id: Fix.fundID,
            in: repository.snapshot,
            now: repository.now,
        )
        // The form shows the item's account for 1 Dec; changing only its amount saves.
        let shown = try #require(LedgerBook.activeScheduledItems(in: repository.snapshot).first)
        var form = shown.resolved(for: december)
        form.occurrences = shown.occurrences
        form.amount = 26_000
        _ = try repository.useCases()
            .update(
                form,
                editing: ScheduledOccurrenceSave(occurrence: december, dueDay: december, scope: .thisOccurrence),
                payee: nil,
            )
        try edit(id, in: repository, occurrence: Fix.day(2027, 1, 1), scope: .thisOccurrence) { $0.amount = 27_000 }
        repository.snapshot.accounts.append(fund)
        let back = try stored(id, repository).resolved(for: december)
        #expect(back.accountID == Fix.fundID)
        #expect(back.amount == 26_000)
    }
}

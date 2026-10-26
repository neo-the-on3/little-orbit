import Foundation
import LittleOrbitDomain
import Testing

/// The batch behind Undo Import's payee cleanup (#250) does what one `deletingPayee` and one
/// `payeeReferenceCount` per payee did, over transactions and scheduled items, live and deleted.
@Suite("Batch payee cleanup (#250)")
struct ImportUndoPayeeBatchTests {
    static let zone = "Asia/Kolkata"
    static let created = Date(timeIntervalSince1970: 1_780_000_000)
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    let account = Account(name: "Everyday Savings", currencyCode: "INR")
    let payees = ["Corner Shop", "Cinema Hall", "Gym", "Kiosk", "Bakery"].map { Payee(name: $0) }

    func transaction(_ payee: Int, deleted: Bool = false) -> Transaction {
        var transaction = Transaction(type: .expense, amount: 10, timeZoneID: Self.zone, accountID: account.id)
        transaction.payeeID = payees[payee].id
        transaction.deletedAt = deleted ? Self.created : nil
        return transaction
    }

    func scheduled(_ payee: Int, deleted: Bool = false) -> ScheduledItem {
        ScheduledItem(
            amount: 10,
            accountID: account.id,
            payeeID: payees[payee].id,
            startDay: CalendarDay(year: 2026, month: 11, day: 1),
            timeZoneID: Self.zone,
            createdAt: Self.created,
            deletedAt: deleted ? Self.created : nil,
        )
    }

    /// Made afresh on each read, so a test reads it once. Corner Shop: a live transaction. Cinema Hall: a deleted
    /// transaction only. Gym: a live scheduled item. Kiosk: a deleted scheduled item only. Bakery: nothing.
    var snapshot: LedgerSnapshot {
        LedgerSnapshot(
            accounts: [account],
            transactions: [transaction(0), transaction(1, deleted: true), transaction(0)],
            payees: payees,
            scheduledItems: [scheduled(2), scheduled(3, deleted: true)],
        )
    }

    @Test("Payees in use are the ones with a reference count above zero")
    func inUseMatchesCounts() {
        let snapshot = snapshot
        let ids = Set(payees.map(\.id))
        let counted = ids.filter { snapshot.payeeReferenceCount($0) > 0 }
        #expect(snapshot.payeesInUse(among: ids) == counted)
        #expect(snapshot.payeesInUse(among: ids) == [payees[0].id, payees[2].id])
        #expect(snapshot.payeesInUse(among: [payees[1].id, payees[4].id]).isEmpty)
        #expect(snapshot.payeesInUse(among: []).isEmpty)
    }

    @Test("Deleting payees as a batch leaves the same ledger as deleting each in turn")
    func batchMatchesOneByOne() throws {
        let snapshot = snapshot
        for ids in [payees.map(\.id), [payees[1].id, payees[3].id, payees[4].id], [payees[2].id]] {
            var oneByOne = snapshot
            for id in ids {
                oneByOne = try LedgerBook.deletingPayee(id: id, in: oneByOne, now: Self.now)
            }
            let batch = try LedgerBook.deletingPayees(ids: ids, in: snapshot, now: Self.now)
            #expect(batch == oneByOne)
        }
    }

    @Test("A batch with a payee that isn't there throws and changes nothing; an empty batch changes nothing")
    func unknownAndEmpty() throws {
        let snapshot = snapshot
        #expect(throws: LedgerValidationError.unknownPayee) {
            try LedgerBook.deletingPayees(ids: [payees[1].id, UUID()], in: snapshot, now: Self.now)
        }
        #expect(try LedgerBook.deletingPayees(ids: [], in: snapshot, now: Self.now) == snapshot)
    }

    @Test("The one-by-one default counts a repeated id once, as the batch does")
    @MainActor
    func defaultDropsRepeatedIDs() throws {
        let repository = try FakeLedgerRepository()
        for payee in payees {
            try repository.savePayee(payee)
        }
        let ids = [payees[3].id, payees[1].id, payees[3].id, payees[1].id]
        let batch = try LedgerBook.deletingPayees(ids: ids, in: repository.snapshot, now: Self.now)
        try repository.deletePayees(ids: ids)
        #expect(repository.snapshot.payees == batch.payees)
        #expect(repository.snapshot.payees.map(\.name) == ["Corner Shop", "Gym", "Bakery"])
    }
}

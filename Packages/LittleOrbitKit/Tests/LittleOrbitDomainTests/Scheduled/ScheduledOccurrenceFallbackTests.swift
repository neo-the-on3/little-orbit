import Foundation
import LittleOrbitDomain
import Testing

/// An occurrence's own account that's gone, and an item that stops repeating (#202: Tech Architect B1 and Tester's
/// Mac pass at 66697b7). Made-up data.
extension ScheduledOccurrenceEditTests {
    private func backup(_ ledger: LedgerSnapshot) -> BackupContents {
        BackupContents(
            manifest: BackupManifest(
                kind: .automatic,
                createdAt: Fix.created,
                nameIndex: 1,
                schemaVersion: "1.0.0",
                accountCount: ledger.accounts.count,
                transactionCount: ledger.transactions.count,
                attachmentCount: 0,
            ),
            ledger: ledger,
        )
    }

    /// Rent on Everyday Savings, with 1 Dec alone paying from Long Term Fund; today is 20 Nov.
    private func rentWithOwnAccount() throws -> FakeScheduledRepositoryAndID {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 11, 20))
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .thisOccurrence) {
            $0.accountID = Fix.fundID
            $0.amount = 26_000
        }
        return (repository, rent.id)
    }

    @Test("#202 B1: delete the account one occurrence pays from, then back up and restore; it follows the item's")
    func deletedEditAccountBackupRestores() throws {
        let (repository, id) = try rentWithOwnAccount()
        repository.snapshot = try LedgerBook.deletingAccount(
            id: Fix.fundID,
            in: repository.snapshot,
            now: repository.now,
        )
        // The item stays active, and 1 Dec now shows the item's account with its own amount.
        repository.now = Fix.date(2026, 12, 1)
        let due = try #require(try repository.useCases().listing().board.dueToday.first)
        #expect(due.occurrenceItem.accountID == Fix.savingsID)
        #expect(due.occurrenceItem.amount == 26_000)
        // Every backup made now restores, rather than being refused as damaged.
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let decoded = try codec.decode(try codec.encode(backup(repository.snapshot)))
        try LedgerBook.validateStoredScheduledItems(in: decoded.ledger)
        let restored = try #require(decoded.ledger.scheduledItems.first { $0.id == id })
        #expect(restored.edit(for: Fix.day(2026, 12, 1))?.fields == [.amount])
        #expect(restored.occurrence(on: Fix.day(2026, 12, 1))?.outcome == .edited)
        // Restored, 1 Dec pays once from Everyday Savings with its own amount.
        let after = FakeScheduleRepository(decoded.ledger)
        after.now = repository.now
        let paid = try #require(try after.useCases().payNow(itemID: id, occurrence: Fix.day(2026, 12, 1)))
        #expect(paid.accountID == Fix.savingsID)
        #expect(paid.amount == 26_000)
        #expect(try after.useCases().payNow(itemID: id, occurrence: Fix.day(2026, 12, 1)) == nil)
    }

    @Test("#202 B1: Pay after the delete uses the item's account; Undo of the delete gives 1 Dec its own back")
    func deletedEditAccountFallsBackUntilUndo() throws {
        let (repository, id) = try rentWithOwnAccount()
        let fund = try #require(repository.snapshot.accounts.first { $0.id == Fix.fundID })
        repository.snapshot = try LedgerBook.deletingAccount(
            id: Fix.fundID,
            in: repository.snapshot,
            now: repository.now,
        )
        repository.snapshot.accounts.append(fund)
        let undone = try #require(LedgerBook.activeScheduledItems(in: repository.snapshot).first { $0.id == id })
        #expect(undone.resolved(for: Fix.day(2026, 12, 1)).accountID == Fix.fundID)
        repository.snapshot = try LedgerBook.deletingAccount(
            id: Fix.fundID,
            in: repository.snapshot,
            now: repository.now,
        )
        let paid = try #require(try repository.useCases().payNow(itemID: id, occurrence: Fix.day(2026, 12, 1)))
        #expect(paid.accountID == Fix.savingsID)
    }

    @Test("#202 B1: a backup whose occurrence edit names an unknown account restores without that account")
    func unknownEditAccountRestores() throws {
        let (repository, id) = try rentWithOwnAccount()
        var ledger = repository.snapshot
        let index = try #require(ledger.scheduledItems[0].occurrences.firstIndex { $0.outcome == .edited })
        ledger.scheduledItems[0].occurrences[index].edit?.accountID = UUID()
        let accountOnly = ScheduledOccurrence(
            id: UUID(),
            day: Fix.day(2027, 1, 1),
            outcome: .edited,
            edit: ScheduledOccurrenceEdit(fields: [.account], accountID: UUID()),
            createdAt: Fix.created,
        )
        ledger.scheduledItems[0].occurrences.append(accountOnly)
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let decoded = try codec.decode(try codec.encode(backup(ledger)))
        let restored = try #require(decoded.ledger.scheduledItems.first { $0.id == id })
        #expect(
            restored.edit(for: Fix.day(2026, 12, 1)) == ScheduledOccurrenceEdit(fields: [.amount], amount: 26_000)
        )
        // An occurrence left with nothing of its own is an open one again.
        #expect(restored.occurrence(on: Fix.day(2027, 1, 1))?.edit == nil)
        #expect(restored.occurrence(on: Fix.day(2027, 1, 1))?.outcome == .pending)
    }

    /// Phone Plan, ₹700 monthly on the 20th from Rewards Card (the fund here), with 20 Aug alone ₹651 on Everyday
    /// Savings, then set to Never from the form on 20 Aug.
    private func phonePlanMadeOneOff(today: CalendarDay) throws -> FakeScheduledRepositoryAndID {
        var phone = Fix.rent(amount: 700, start: Fix.day(2026, 8, 20), automatic: false)
        phone.accountID = Fix.fundID
        phone.details = "Phone Plan"
        let repository = try scene(phone, today: today)
        try edit(phone.id, in: repository, occurrence: Fix.day(2026, 8, 20), scope: .thisOccurrence) {
            $0.amount = 651
            $0.accountID = Fix.savingsID
        }
        try edit(phone.id, in: repository, occurrence: Fix.day(2026, 8, 20), scope: .allFuture) {
            $0.repeatRule = .never
        }
        return (repository, phone.id)
    }

    @Test("#202 Tester: an item set to Never from its occurrence takes that occurrence's values, and the form saves")
    func oneOffTakesTheOccurrenceValues() throws {
        let (repository, id) = try phonePlanMadeOneOff(today: Fix.day(2026, 8, 10))
        var item = try stored(id, repository)
        #expect(item.amount == 651)
        #expect(item.accountID == Fix.savingsID)
        #expect(item.occurrences.isEmpty)
        // The one-off form (no Due Date row) saves ₹700, and the row and Pay Now follow it.
        item.amount = 700
        try repository.useCases().save(item)
        let row = try #require(try repository.useCases().listing().board.upcoming.first)
        #expect(row.occurrenceItem.amount == 700)
        repository.now = Fix.date(2026, 8, 20)
        let paid = try #require(try repository.useCases().payNow(itemID: id, occurrence: Fix.day(2026, 8, 20)))
        #expect(paid.amount == 700)
        #expect(paid.accountID == Fix.savingsID)
        #expect(try repository.useCases().payNow(itemID: id, occurrence: Fix.day(2026, 8, 20)) == nil)
        // Undo Pay (#201) puts back the record that was there before: none, so it's open again on the item's values.
        #expect(try stored(id, repository).occurrence(on: Fix.day(2026, 8, 20))?.edit == nil)
    }

    @Test("#202 Tester: overdue days kept from the old rule keep the old ₹700 on Rewards Card (S58, D336.1)")
    func oneOffKeepsOldValuesOnKeptDays() throws {
        let (repository, id) = try phonePlanMadeOneOff(today: Fix.day(2026, 10, 26))
        let item = try stored(id, repository)
        #expect(item.amount == 651)
        let overdue = try repository.useCases().listing().board.overdue
        #expect(overdue.map(\.key) == [Fix.day(2026, 8, 20), Fix.day(2026, 9, 20), Fix.day(2026, 10, 20)])
        #expect(overdue.map(\.occurrenceItem.amount) == [651, 700, 700])
        #expect(overdue.map(\.occurrenceItem.accountID) == [Fix.savingsID, Fix.fundID, Fix.fundID])
    }

    @Test("#202 Tester: a one-off saved at 66697b7 with its occurrence's own values follows its form on the next save")
    func oneOffWithStoredEditFollowsTheForm() throws {
        var phone = Fix.rent(amount: 700, start: Fix.day(2026, 8, 20), rule: .never, automatic: false)
        phone.accountID = Fix.fundID
        let repository = try scene(phone, today: Fix.day(2026, 8, 10))
        let record = ScheduledOccurrence(
            id: ScheduledKey.occurrenceID(item: phone.id, day: phone.startDay),
            day: phone.startDay,
            outcome: .edited,
            edit: ScheduledOccurrenceEdit(fields: [.amount, .account], amount: 651, accountID: Fix.savingsID),
            createdAt: Fix.created,
        )
        repository.snapshot.scheduledItems[0].occurrences = [record]
        try repository.useCases().save(try stored(phone.id, repository))
        let row = try #require(try repository.useCases().listing().board.upcoming.first)
        #expect(row.occurrenceItem.amount == 700)
        #expect(row.occurrenceItem.accountID == Fix.fundID)
    }
}

typealias FakeScheduledRepositoryAndID = (repository: FakeScheduleRepository, id: UUID)

import Foundation
import LittleOrbitDomain
import Testing

/// Each occurrence posts exactly once (#26, Product Manager): keyed by the item and the occurrence's day, and
/// recorded in the same save as its transaction.
@MainActor
@Suite("Scheduled posting, exactly once (#26)")
struct ScheduledPostingTests {
    private typealias Fix = ScheduledFixture

    private func repository(with items: [ScheduledItem], today: Date = Fix.date(2026, 10, 20)) throws
        -> FakeScheduleRepository
    {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        for item in items {
            try repository.useCases().save(item)
        }
        repository.now = today
        return repository
    }

    @Test("Missed occurrences after days away: Aug, Sep and Oct post once each, dated on their days")
    func missedOccurrences() throws {
        let rent = Fix.rent()
        let repository = try repository(with: [rent])
        let result = try repository.useCases().catchUp(atLaunch: true)
        #expect(result.posted.count == 3)
        let posted = repository.posted(for: rent.id)
        #expect(
            posted.map(TransactionTiming.day(of:)) == [
                Fix.day(2026, 8, 1), Fix.day(2026, 9, 1), Fix.day(2026, 10, 1),
            ]
        )
        #expect(
            posted.allSatisfy { $0.amount == 25_000 && $0.accountID == Fix.savingsID && $0.categoryID == Fix.housingID }
        )
        #expect(repository.snapshot.scheduledItems[0].occurrences.map(\.outcome) == [.posted, .posted, .posted])
        #expect(
            Set(repository.snapshot.scheduledItems[0].occurrences.compactMap(\.transactionID)) == Set(posted.map(\.id))
        )
    }

    @Test("Re-running posting twice, or from a second window or launch, records nothing more")
    func runTwice() throws {
        let rent = Fix.rent()
        let repository = try repository(with: [rent])
        _ = try repository.useCases().catchUp(atLaunch: true)
        let again = try repository.useCases().catchUp(atLaunch: false)
        let otherWindow = try repository.useCases().catchUp(atLaunch: false)
        let relaunch = try repository.useCases().catchUp(atLaunch: true)
        #expect(again.posted.isEmpty && otherWindow.posted.isEmpty && relaunch.posted.isEmpty)
        #expect(repository.posted(for: rent.id).count == 3)
    }

    @Test("Pay now twice on the same occurrence records one transaction, and catch-up then skips it")
    func payTwice() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try repository(with: [rent])
        let useCases = repository.useCases()
        let first = try useCases.payNow(itemID: rent.id, occurrence: Fix.day(2026, 8, 1))
        let second = try useCases.payNow(itemID: rent.id, occurrence: Fix.day(2026, 8, 1))
        #expect(first != nil)
        #expect(second == nil)
        #expect(repository.posted(for: rent.id).count == 1)
        // Pay now is dated today, and keeps the occurrence's own day as its key.
        #expect(first.map(TransactionTiming.day(of:)) == Fix.day(2026, 10, 20))
        #expect(first?.id == ScheduledKey.transactionID(item: rent.id, day: Fix.day(2026, 8, 1)))
    }

    @Test("A clock turned back, then forward again, never posts an occurrence twice")
    func clockChange() throws {
        let rent = Fix.rent()
        let repository = try repository(with: [rent])
        _ = try repository.useCases().catchUp(atLaunch: true)
        repository.now = Fix.date(2026, 8, 15)
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
        repository.now = Fix.date(2026, 10, 25)
        #expect(try repository.useCases().catchUp(atLaunch: false).posted.isEmpty)
        repository.now = Fix.date(2026, 11, 1, 0)
        #expect(try repository.useCases().catchUp(atLaunch: false).posted.count == 1)
        #expect(repository.posted(for: rent.id).count == 4)
    }

    @Test("Today is the device's day: just after midnight in Kolkata is already the 1st")
    func deviceDay() throws {
        let rent = Fix.rent(start: Fix.day(2026, 11, 1))
        // 18:45 UTC on 31 Oct is 00:15 on 1 Nov in Kolkata.
        let repository = try repository(with: [rent], today: Fix.date(2026, 11, 1, 0) + 15 * 60)
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.count == 1)
        let london = try repository.useCases(zone: "Europe/London").catchUp(atLaunch: false)
        #expect(london.posted.isEmpty)
    }

    @Test("Deleting a posted transaction doesn't post its occurrence again")
    func deletedTransactionStaysSettled() throws {
        let rent = Fix.rent()
        let repository = try repository(with: [rent])
        _ = try repository.useCases().catchUp(atLaunch: true)
        let first = try #require(repository.posted(for: rent.id).first)
        repository.snapshot = try LedgerBook.deletingTransaction(
            id: first.id,
            in: repository.snapshot,
            now: repository.now,
        )
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
        #expect(repository.posted(for: rent.id).count == 2)
    }

    @Test("A recorded transaction with no settled record (an edited backup) is recorded, not posted again")
    func transactionWithoutRecord() throws {
        let rent = Fix.rent()
        let repository = try repository(with: [rent])
        _ = try repository.useCases().catchUp(atLaunch: true)
        repository.snapshot.scheduledItems[0].occurrences.removeAll { $0.day == Fix.day(2026, 9, 1) }
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
        #expect(repository.posted(for: rent.id).count == 3)
        #expect(repository.snapshot.scheduledItems[0].occurrence(on: Fix.day(2026, 9, 1))?.outcome == .posted)
    }

    @Test("Month-end: skipping 28 Feb keeps the 31st, so 31 Mar is next (D24)")
    func skipKeepsAnchor() throws {
        let item = Fix.rent(start: Fix.day(2027, 1, 31), automatic: false)
        let repository = try repository(with: [item], today: Fix.date(2027, 2, 28))
        let useCases = repository.useCases()
        try useCases.payNow(itemID: item.id, occurrence: Fix.day(2027, 1, 31))
        try useCases.skip(itemID: item.id, occurrence: Fix.day(2027, 2, 28))
        let board = try useCases.listing().board
        #expect(board.upcoming.map(\.day) == [Fix.day(2027, 3, 31)])
        #expect(board.overdue.isEmpty && board.dueToday.isEmpty)
        #expect(repository.posted(for: item.id).count == 1)
    }

    @Test("Pay now on a day that isn't an occurrence is refused")
    func notAnOccurrence() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try repository(with: [rent])
        #expect(throws: LedgerValidationError.notAnOccurrence) {
            try repository.useCases().payNow(itemID: rent.id, occurrence: Fix.day(2026, 8, 2))
        }
    }

    @Test("Editing the amount changes later postings only; recorded transactions stay")
    func editAmount() throws {
        var rent = Fix.rent()
        let repository = try repository(with: [rent])
        _ = try repository.useCases().catchUp(atLaunch: true)
        rent.amount = 26_000
        try repository.useCases().save(rent)
        repository.now = Fix.date(2026, 11, 2)
        _ = try repository.useCases().catchUp(atLaunch: false)
        #expect(repository.posted(for: rent.id).map(\.amount) == [25_000, 25_000, 25_000, 26_000])
    }

    @Test("A form saved after another window posted keeps the stored settled occurrences")
    func staleFormKeepsOccurrences() throws {
        let rent = Fix.rent()
        let repository = try repository(with: [rent])
        var stale = repository.snapshot.scheduledItems[0]
        _ = try repository.useCases().catchUp(atLaunch: true)
        stale.details = "Flat rent"
        try repository.useCases().save(stale)
        #expect(repository.snapshot.scheduledItems[0].occurrences.count == 3)
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
    }

    /// D426.1: 20 Oct is recorded, so October has its occurrence and the new rule's next day is 25 Nov.
    @Test("D114: moving the anchor after Aug–Oct were recorded applies going forward, never to past days")
    func ruleChangeGoesForward() throws {
        var phone = Fix.rent(start: Fix.day(2026, 8, 20))
        let repository = try repository(with: [phone], today: Fix.date(2026, 10, 24))
        _ = try repository.useCases().catchUp(atLaunch: true)
        #expect(repository.posted(for: phone.id).count == 3)
        phone.startDay = Fix.day(2026, 8, 25)
        try repository.useCases().save(phone)
        #expect(repository.snapshot.scheduledItems[0].resumesOn == Fix.day(2026, 10, 24))
        let board = try repository.useCases().listing().board
        #expect(board.upcoming.map(\.day) == [Fix.day(2026, 11, 25)])
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
        #expect(repository.posted(for: phone.id).count == 3)
    }

    @Test("Deleting an item stops its postings and leaves its recorded transactions")
    func deleteItem() throws {
        let rent = Fix.rent()
        let repository = try repository(with: [rent])
        _ = try repository.useCases().catchUp(atLaunch: true)
        try repository.useCases().delete(id: rent.id)
        repository.now = Fix.date(2027, 3, 1)
        #expect(try repository.useCases().catchUp(atLaunch: true).posted.isEmpty)
        #expect(repository.posted(for: rent.id).count == 3)
        #expect(try repository.useCases().listing().board.isEmpty)
    }

    @Test("D288.1: an item on a deleted account waits; Undo brings it back as missed; a relaunch removes it")
    func deletedAccount() throws {
        let transfer = Fix.transfer(start: Fix.day(2026, 11, 5), end: nil)
        var automatic = transfer
        automatic.processesAutomatically = true
        let repository = try repository(with: [automatic], today: Fix.date(2026, 11, 1))
        let fund = try #require(repository.snapshot.accounts.first { $0.id == Fix.fundID })
        repository.snapshot = try LedgerBook.deletingAccount(
            id: Fix.fundID,
            in: repository.snapshot,
            now: repository.now,
        )
        repository.now = Fix.date(2026, 11, 6)
        #expect(try repository.useCases().catchUp(atLaunch: false).posted.isEmpty)
        #expect(try repository.useCases().listing().board.isEmpty)
        // Undo Delete Account puts the account back with the same ID: the missed 5 Nov posts.
        repository.snapshot.accounts.append(fund)
        #expect(try repository.useCases().catchUp(atLaunch: false).posted.count == 1)
        // Deleted again, then a relaunch: the item goes for good.
        repository.snapshot = try LedgerBook.deletingAccount(
            id: Fix.fundID,
            in: repository.snapshot,
            now: repository.now,
        )
        let launch = try repository.useCases().catchUp(atLaunch: true)
        #expect(launch.removedItemIDs == [automatic.id])
        #expect(repository.snapshot.scheduledItems.isEmpty)
    }

    @Test("An item that can't post is left as it was, and the others still post")
    func failureIsolation() throws {
        var broken = Fix.rent()
        broken.payeeID = Fix.bakeryID
        let salary = ScheduledItem(
            type: .income,
            amount: 52_500,
            accountID: Fix.savingsID,
            categoryID: Fix.salaryID,
            startDay: Fix.day(2026, 10, 1),
            processesAutomatically: true,
            timeZoneID: Fix.zone,
            createdAt: Fix.created,
        )
        let repository = try repository(with: [broken, salary])
        repository.snapshot.payees.removeAll()
        let result = try repository.useCases().catchUp(atLaunch: true)
        #expect(result.failedItemIDs == [broken.id])
        #expect(result.posted.map(\.scheduledTemplateID) == [salary.id])
        #expect(repository.snapshot.scheduledItems.first { $0.id == broken.id }?.occurrences.isEmpty == true)
    }

    @Test("Saving is blocked for an end before the start, an amount of 0 or a repeat of 0")
    func validation() throws {
        let repository = FakeScheduleRepository()
        #expect(throws: LedgerValidationError.scheduleEndsBeforeStart) {
            try repository.useCases().save(Fix.rent(start: Fix.day(2026, 11, 1), end: Fix.day(2026, 10, 1)))
        }
        #expect(throws: LedgerValidationError.invalidAmount) {
            try repository.useCases().save(Fix.rent(amount: 0))
        }
        #expect(throws: LedgerValidationError.scheduleRepeatOutOfRange) {
            try repository.useCases().save(Fix.rent(rule: .every(0, .month)))
        }
        try repository.useCases().save(Fix.rent(amount: Decimal(string: "999999999.99")!))
        #expect(repository.snapshot.scheduledItems.count == 1)
    }

    @Test("Deleting a payee or a category updates scheduled items too")
    func referencesFollow() throws {
        var rent = Fix.rent()
        rent.payeeID = Fix.bakeryID
        let repository = try repository(with: [rent])
        #expect(repository.snapshot.payeeReferenceCount(Fix.bakeryID) == 1)
        repository.snapshot = try LedgerBook.deletingPayee(
            id: Fix.bakeryID,
            in: repository.snapshot,
            now: repository.now,
        )
        #expect(repository.snapshot.scheduledItems[0].payeeID == nil)
        repository.snapshot = try LedgerBook.deletingCategory(
            id: Fix.housingID,
            reassigningTo: nil,
            in: repository.snapshot,
            now: repository.now,
        )
        #expect(repository.snapshot.scheduledItems[0].categoryID == nil)
    }
}

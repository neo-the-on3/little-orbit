import Foundation
import LittleOrbitDomain
import Testing

/// Moved occurrences and stored edits (Tech Architect B1, NB 2, NB 4 and NB 5 on #202; D346.4), beside the other
/// occurrence edit tests. Made-up data.
extension ScheduledOccurrenceEditTests {
    @Test("Tech Architect B1: 1 Dec moved past 1 Jan to 5 Jan leaves 1 Jan as the next occurrence, then 5 Jan")
    func moveLaterKeepsTheNextOne() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 11, 20))
        try edit(
            rent.id,
            in: repository,
            occurrence: Fix.day(2026, 12, 1),
            dueDay: Fix.day(2027, 1, 5),
            scope: .thisOccurrence,
        )
        let slots = try next(rent.id, repository)
        #expect(slots.map(\.day) == [Fix.day(2027, 1, 1), Fix.day(2027, 1, 5), Fix.day(2027, 2, 1)])
        #expect(slots.map(\.key) == [Fix.day(2027, 1, 1), Fix.day(2026, 12, 1), Fix.day(2027, 2, 1)])
    }

    @Test("NB 2, D336.1: 1 Nov moved to 15 Oct is overdue; a start edit keeps it overdue on 15 Oct")
    func ruleChangeKeepsOccurrenceMovedIntoThePast() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 10, 20))
        for month in 8...10 {
            try repository.useCases().payNow(itemID: rent.id, occurrence: Fix.day(2026, month, 1))
        }
        try edit(
            rent.id,
            in: repository,
            occurrence: Fix.day(2026, 11, 1),
            dueDay: Fix.day(2026, 10, 15),
            scope: .thisOccurrence,
        )
        #expect(try repository.useCases().listing().board.overdue.map(\.day) == [Fix.day(2026, 10, 15)])
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .allFuture) {
            $0.startDay = Fix.day(2026, 8, 5)
        }
        let board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day).contains(Fix.day(2026, 10, 15)))
    }

    @Test("D346.4: the catch-up hint lists a moved automatic occurrence on the day it was recorded, 3 Dec")
    func catchUpHintUsesTheMovedDay() throws {
        let rent = Fix.rent()
        let repository = try scene(rent, today: Fix.day(2026, 11, 20))
        _ = try repository.useCases().catchUp(atLaunch: true)
        try edit(
            rent.id,
            in: repository,
            occurrence: Fix.day(2026, 12, 1),
            dueDay: Fix.day(2026, 12, 3),
            scope: .thisOccurrence,
        )
        repository.now = Fix.date(2026, 12, 4)
        let result = try repository.useCases().catchUp(atLaunch: true)
        #expect(result.recordedByItem == [ScheduledCatchUpGroup(itemID: rent.id, days: [Fix.day(2026, 12, 3)])])
    }

    @Test("NB 5: a restored occurrence edit with no values, or an amount of zero, is refused")
    func restoreChecksEditValues() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 11, 20))
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .thisOccurrence) {
            $0.amount = 26_000
        }
        try LedgerBook.validateStoredScheduledItems(in: repository.snapshot)
        let index = try #require(repository.snapshot.scheduledItems[0].occurrences.firstIndex { $0.outcome == .edited })
        var zero = repository.snapshot
        zero.scheduledItems[0].occurrences[index].edit?.amount = 0
        #expect(throws: LedgerValidationError.invalidAmount) { try LedgerBook.validateStoredScheduledItems(in: zero) }
        var empty = repository.snapshot
        empty.scheduledItems[0].occurrences[index].edit = nil
        #expect(throws: LedgerValidationError.invalidAmount) { try LedgerBook.validateStoredScheduledItems(in: empty) }
    }

    @Test("#202 B1: a stored occurrence edit on an account the ledger doesn't have isn't refused")
    func restoreAcceptsUnknownEditAccounts() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 11, 20))
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .thisOccurrence) {
            $0.accountID = Fix.fundID
        }
        let index = try #require(repository.snapshot.scheduledItems[0].occurrences.firstIndex { $0.outcome == .edited })
        var unknown = repository.snapshot
        unknown.scheduledItems[0].occurrences[index].edit?.accountID = UUID()
        unknown.scheduledItems[0].occurrences[index].edit?.transferAccountID = UUID()
        try LedgerBook.validateStoredScheduledItems(in: unknown)
    }

    @Test("NB 4: a whole-item save from a form on an occurrence with its own amount keeps the item's own amount")
    func wholeItemSaveKeepsItemValues() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 10, 20))
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .thisOccurrence) {
            $0.amount = 30_000
        }
        // The form on 1 Dec shows 30,000; switching the item to Never changes nothing else.
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .allFuture) {
            $0.repeatRule = .never
            $0.details = "Rent, last month"
        }
        let item = try stored(rent.id, repository)
        #expect(item.repeatRule == .never)
        #expect(item.amount == 25_000)
        #expect(item.details == "Rent, last month")
    }

    @Test("NB 4: a type change keeps the item's own amount and takes the form's category")
    func typeChangeKeepsItemAmount() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 10, 20))
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .thisOccurrence) {
            $0.amount = 30_000
        }
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .allFuture) {
            $0.type = .income
            $0.categoryID = Fix.salaryID
        }
        let item = try stored(rent.id, repository)
        #expect(item.type == .income)
        #expect(item.amount == 25_000)
        #expect(item.categoryID == Fix.salaryID)
    }
}

import Foundation
import LittleOrbitDomain
import Testing

/// Occurrence edits (#197 item 3; #26 D45, D106, D111, D114, D115): "This occurrence only" and "All future
/// occurrences", with each occurrence still recorded once under its own key. Made-up data.
@MainActor
@Suite("Scheduled occurrence edits (#26 D45, D106, D111, D114, D115)")
struct ScheduledOccurrenceEditTests {
    typealias Fix = ScheduledFixture

    /// A Rent item saved on 1 Jul 2026, with the clock then moved to `today`.
    func scene(
        _ item: ScheduledItem,
        today: CalendarDay = ScheduledFixture.day(2026, 10, 20),
    ) throws -> FakeScheduleRepository {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        try repository.useCases().save(item)
        repository.now = Fix.date(today.year, today.month, today.day)
        return repository
    }

    func stored(_ id: UUID, _ repository: FakeScheduleRepository) throws -> ScheduledItem {
        try #require(repository.snapshot.scheduledItems.first { $0.id == id })
    }

    /// Saves `change` applied to the stored item, as the form opened on the occurrence `key` does.
    func edit(
        _ id: UUID,
        in repository: FakeScheduleRepository,
        occurrence key: CalendarDay,
        dueDay: CalendarDay? = nil,
        scope: ScheduledEditScope,
        _ change: (inout ScheduledItem) -> Void = { _ in },
    ) throws {
        let current = try stored(id, repository)
        var item = current.resolved(for: key)
        item.occurrences = current.occurrences
        change(&item)
        let save = ScheduledOccurrenceSave(occurrence: key, dueDay: dueDay ?? current.dueDay(of: key), scope: scope)
        try repository.useCases().save(item, editing: save)
    }

    func next(_ id: UUID, _ repository: FakeScheduleRepository, count: Int = 3) throws -> [ScheduledSlot] {
        var item = try stored(id, repository)
        var slots: [ScheduledSlot] = []
        let today = repository.useCases().today()
        while slots.count < count, let slot = ScheduleCalendar.nextOccurrence(of: item, after: today) {
            slots.append(slot)
            let edit = item.edit(for: slot.key)
            item.occurrences.removeAll { $0.day == slot.key }
            item.occurrences.append(
                ScheduledOccurrence(id: UUID(), day: slot.key, outcome: .skipped, edit: edit, createdAt: Fix.created)
            )
        }
        return slots
    }

    func amounts(_ id: UUID, _ repository: FakeScheduleRepository, _ keys: [CalendarDay]) throws -> [Decimal] {
        let item = try stored(id, repository)
        return keys.map { item.resolved(for: $0).amount }
    }

    @Test("D45: 1 Dec to ₹26,000 with This occurrence only; 1 Jan stays ₹25,000 on the 1st and the anchor holds")
    func thisOccurrenceAmount() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 11, 20))
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .thisOccurrence) {
            $0.amount = 26_000
        }
        let item = try stored(rent.id, repository)
        #expect(item.amount == 25_000)
        #expect(item.startDay == Fix.day(2026, 8, 1))
        #expect(try amounts(rent.id, repository, [Fix.day(2026, 12, 1), Fix.day(2027, 1, 1)]) == [26_000, 25_000])
        #expect(
            try next(rent.id, repository).map(\.day) == [
                Fix.day(2026, 12, 1), Fix.day(2027, 1, 1), Fix.day(2027, 2, 1),
            ]
        )
    }

    @Test("D45, S58: All future occurrences changes 1 Dec onwards; the overdue 1 Nov stays ₹25,000 and overdue")
    func allFutureAmountKeepsEarlierOpenDays() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 11, 20))
        try repository.useCases().payNow(itemID: rent.id, occurrence: Fix.day(2026, 8, 1))
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .allFuture) { $0.amount = 26_000 }
        let item = try stored(rent.id, repository)
        #expect(item.amount == 26_000)
        let board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [Fix.day(2026, 9, 1), Fix.day(2026, 10, 1), Fix.day(2026, 11, 1)])
        #expect(board.overdue.map(\.occurrenceItem.amount) == [25_000, 25_000, 25_000])
        #expect(try amounts(rent.id, repository, [Fix.day(2026, 12, 1), Fix.day(2027, 1, 1)]) == [26_000, 26_000])
        // Recorded transactions never change.
        #expect(repository.posted(for: rent.id).map(\.amount) == [25_000])
    }

    @Test("S57: moving 28 Feb 2027 to 26 Feb with This occurrence only keeps 31 Mar and 30 Apr")
    func thisOccurrenceDateKeepsAnchor() throws {
        let card = Fix.rent(amount: 4_000, start: Fix.day(2027, 1, 31), automatic: false)
        let repository = try scene(card, today: Fix.day(2027, 2, 1))
        try edit(
            card.id,
            in: repository,
            occurrence: Fix.day(2027, 2, 28),
            dueDay: Fix.day(2027, 2, 26),
            scope: .thisOccurrence,
        )
        let slots = try next(card.id, repository)
        #expect(slots.map(\.day) == [Fix.day(2027, 2, 26), Fix.day(2027, 3, 31), Fix.day(2027, 4, 30)])
        #expect(slots.first?.key == Fix.day(2027, 2, 28))
        #expect(try stored(card.id, repository).startDay == Fix.day(2027, 1, 31))
    }

    @Test("S61: moving 30 Apr 2027 to 15 Apr with All future occurrences gives 15 Apr, 15 May, 15 Jun")
    func allFutureDateMovesAnchor() throws {
        let card = Fix.rent(amount: 4_000, start: Fix.day(2027, 1, 31), automatic: false)
        let repository = try scene(card, today: Fix.day(2027, 4, 1))
        try repository.useCases().skip(itemID: card.id, occurrence: Fix.day(2027, 1, 31))
        try repository.useCases().skip(itemID: card.id, occurrence: Fix.day(2027, 2, 28))
        try repository.useCases().skip(itemID: card.id, occurrence: Fix.day(2027, 3, 31))
        try edit(
            card.id,
            in: repository,
            occurrence: Fix.day(2027, 4, 30),
            dueDay: Fix.day(2027, 4, 15),
            scope: .allFuture,
        )
        #expect(
            try next(card.id, repository).map(\.day) == [
                Fix.day(2027, 4, 15), Fix.day(2027, 5, 15), Fix.day(2027, 6, 15),
            ]
        )
        #expect(try repository.useCases().listing().board.overdue.isEmpty)
    }

    @Test("S70: moving 15 Mar 2027 to 31 Mar with All future occurrences gives 30 Apr, 31 May, 30 Jun")
    func allFutureDateToTheThirtyFirst() throws {
        let water = Fix.rent(amount: 600, start: Fix.day(2027, 3, 15), automatic: false)
        let repository = try scene(water, today: Fix.day(2027, 3, 1))
        try edit(
            water.id,
            in: repository,
            occurrence: Fix.day(2027, 3, 15),
            dueDay: Fix.day(2027, 3, 31),
            scope: .allFuture,
        )
        #expect(
            try next(water.id, repository, count: 4).map(\.day)
                == [Fix.day(2027, 3, 31), Fix.day(2027, 4, 30), Fix.day(2027, 5, 31), Fix.day(2027, 6, 30)]
        )
    }

    @Test("S71: after S61, This occurrence only moving 15 Jun to 20 Jun is followed by 15 Jul")
    func thisOccurrenceAfterAnAnchorMove() throws {
        let card = Fix.rent(amount: 4_000, start: Fix.day(2027, 4, 30), automatic: false)
        let repository = try scene(card, today: Fix.day(2027, 4, 1))
        try edit(
            card.id,
            in: repository,
            occurrence: Fix.day(2027, 4, 30),
            dueDay: Fix.day(2027, 4, 15),
            scope: .allFuture,
        )
        try edit(
            card.id,
            in: repository,
            occurrence: Fix.day(2027, 6, 15),
            dueDay: Fix.day(2027, 6, 20),
            scope: .thisOccurrence,
        )
        #expect(
            try next(card.id, repository, count: 4).map(\.day)
                == [Fix.day(2027, 4, 15), Fix.day(2027, 5, 15), Fix.day(2027, 6, 20), Fix.day(2027, 7, 15)]
        )
    }

    @Test("D111, S73, S75: an All future amount change keeps 15 Jun's own ₹4,500; skipping it leaves 15 Jul ₹5,000")
    func allFutureKeepsLaterOwnValues() throws {
        let card = Fix.rent(amount: 4_000, start: Fix.day(2027, 5, 15), automatic: false)
        let repository = try scene(card, today: Fix.day(2027, 5, 1))
        try edit(card.id, in: repository, occurrence: Fix.day(2027, 6, 15), scope: .thisOccurrence) {
            $0.amount = 4_500
        }
        try edit(card.id, in: repository, occurrence: Fix.day(2027, 5, 15), scope: .allFuture) { $0.amount = 5_000 }
        let keys = [Fix.day(2027, 5, 15), Fix.day(2027, 6, 15), Fix.day(2027, 7, 15)]
        #expect(try amounts(card.id, repository, keys) == [5_000, 4_500, 5_000])
        repository.now = Fix.date(2027, 6, 16)
        try repository.useCases().skip(itemID: card.id, occurrence: Fix.day(2027, 6, 15))
        #expect(repository.posted(for: card.id).isEmpty)
        #expect(try amounts(card.id, repository, [Fix.day(2027, 7, 15)]) == [5_000])
    }

    @Test("S74: 15 Jun moved to 20 Jun, then 15 May moved to 10 May for all future: 10 May, 20 Jun, 10 Jul, 10 Aug")
    func anchorMoveKeepsLaterMovedOccurrence() throws {
        let card = Fix.rent(amount: 4_000, start: Fix.day(2027, 5, 15), automatic: false)
        let repository = try scene(card, today: Fix.day(2027, 5, 1))
        try edit(
            card.id,
            in: repository,
            occurrence: Fix.day(2027, 6, 15),
            dueDay: Fix.day(2027, 6, 20),
            scope: .thisOccurrence,
        ) {
            $0.amount = 4_500
        }
        try edit(
            card.id,
            in: repository,
            occurrence: Fix.day(2027, 5, 15),
            dueDay: Fix.day(2027, 5, 10),
            scope: .allFuture,
        )
        let slots = try next(card.id, repository, count: 4)
        #expect(
            slots.map(\.day) == [
                Fix.day(2027, 5, 10), Fix.day(2027, 6, 20), Fix.day(2027, 7, 10), Fix.day(2027, 8, 10),
            ]
        )
        let item = try stored(card.id, repository)
        #expect(item.resolved(for: slots[1].key).amount == 4_500)
        #expect(item.resolved(for: slots[2].key).amount == 4_000)
    }

    @Test("S59: an automatic 1 Dec set to ₹26,000 records ₹26,000 once, under its key; 1 Jan records ₹25,000")
    func catchUpRecordsOwnValuesOnce() throws {
        let rent = Fix.rent()
        let repository = try scene(rent, today: Fix.day(2026, 11, 20))
        _ = try repository.useCases().catchUp(atLaunch: true)
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .thisOccurrence) {
            $0.amount = 26_000
        }
        repository.now = Fix.date(2027, 1, 2)
        _ = try repository.useCases().catchUp(atLaunch: true)
        _ = try repository.useCases().catchUp(atLaunch: true)
        let posted = repository.posted(for: rent.id)
        #expect(posted.map(\.amount) == [25_000, 25_000, 25_000, 25_000, 26_000, 25_000])
        let december = try #require(posted.first { $0.amount == 26_000 })
        #expect(december.id == ScheduledKey.transactionID(item: rent.id, day: Fix.day(2026, 12, 1)))
    }

    @Test("D45: a moved automatic occurrence records on its new day, keyed to its own day, once")
    func movedAutomaticOccurrence() throws {
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
        repository.now = Fix.date(2026, 12, 2)
        #expect(try repository.useCases().catchUp(atLaunch: false).posted.isEmpty)
        repository.now = Fix.date(2026, 12, 3)
        let posted = try repository.useCases().catchUp(atLaunch: false).posted
        #expect(posted.count == 1)
        #expect(posted.first?.id == ScheduledKey.transactionID(item: rent.id, day: Fix.day(2026, 12, 1)))
        #expect(
            posted.first.map { TransactionCalendar.ownDay(of: $0.date, timeZoneID: $0.timeZoneID) }
                == Fix.day(2026, 12, 3)
        )
        #expect(try repository.useCases().catchUp(atLaunch: false).posted.isEmpty)
    }

    @Test("D45: paying a moved occurrence twice records it once; its edit stays on the settled record")
    func payMovedOccurrenceOnce() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 11, 20))
        try edit(
            rent.id,
            in: repository,
            occurrence: Fix.day(2026, 12, 1),
            dueDay: Fix.day(2026, 11, 18),
            scope: .thisOccurrence,
        ) {
            $0.amount = 26_000
        }
        let board = try repository.useCases().listing().board
        let moved = try #require(board.overdue.first { $0.key == Fix.day(2026, 12, 1) })
        #expect(moved.day == Fix.day(2026, 11, 18))
        try repository.useCases().payNow(itemID: rent.id, occurrence: moved.key)
        try repository.useCases().payNow(itemID: rent.id, occurrence: moved.key)
        #expect(repository.posted(for: rent.id).filter { $0.amount == 26_000 }.count == 1)
        #expect(try stored(rent.id, repository).occurrence(on: Fix.day(2026, 12, 1))?.edit?.amount == 26_000)
    }

    @Test("D114, S80: a SERIES-only save changes no occurrence's own values and no recorded transaction")
    func seriesOnlyKeepsEdits() throws {
        let plan = Fix.rent(amount: 499, start: Fix.day(2026, 8, 20), automatic: false)
        let repository = try scene(plan, today: Fix.day(2026, 10, 20))
        for month in 8...10 {
            try repository.useCases().payNow(itemID: plan.id, occurrence: Fix.day(2026, month, 20))
        }
        try edit(plan.id, in: repository, occurrence: Fix.day(2026, 11, 20), scope: .thisOccurrence) { $0.amount = 599 }
        try edit(plan.id, in: repository, occurrence: Fix.day(2026, 11, 20), scope: .allFuture) {
            $0.endDay = Fix.day(2027, 6, 20)
        }
        let item = try stored(plan.id, repository)
        #expect(item.endDay == Fix.day(2027, 6, 20))
        #expect(item.amount == 499)
        #expect(item.resolved(for: Fix.day(2026, 11, 20)).amount == 599)
        #expect(repository.posted(for: plan.id).map(\.amount) == [499, 499, 499])
    }

    @Test("D115, S84: end date and amount in one save; This occurrence only changes 20 Nov only")
    func mixedSaveThisOccurrence() throws {
        let plan = Fix.rent(amount: 499, start: Fix.day(2026, 8, 20), automatic: false)
        let repository = try scene(plan, today: Fix.day(2026, 10, 21))
        for month in 8...10 {
            try repository.useCases().payNow(itemID: plan.id, occurrence: Fix.day(2026, month, 20))
        }
        try edit(plan.id, in: repository, occurrence: Fix.day(2026, 11, 20), scope: .thisOccurrence) {
            $0.endDay = Fix.day(2027, 6, 20)
            $0.amount = 599
        }
        let item = try stored(plan.id, repository)
        #expect(item.endDay == Fix.day(2027, 6, 20))
        #expect(try amounts(plan.id, repository, [Fix.day(2026, 11, 20), Fix.day(2026, 12, 20)]) == [599, 499])
        #expect(repository.posted(for: plan.id).map(\.amount) == [499, 499, 499])
    }

    @Test("D115, S84: the same save with All future occurrences makes 20 Nov onwards ₹599, with the end date")
    func mixedSaveAllFuture() throws {
        let plan = Fix.rent(amount: 499, start: Fix.day(2026, 8, 20), automatic: false)
        let repository = try scene(plan, today: Fix.day(2026, 10, 21))
        for month in 8...10 {
            try repository.useCases().payNow(itemID: plan.id, occurrence: Fix.day(2026, month, 20))
        }
        try edit(plan.id, in: repository, occurrence: Fix.day(2026, 11, 20), scope: .allFuture) {
            $0.endDay = Fix.day(2027, 6, 20)
            $0.amount = 599
        }
        let item = try stored(plan.id, repository)
        #expect(item.endDay == Fix.day(2027, 6, 20))
        #expect(item.amount == 599)
        #expect(try amounts(plan.id, repository, [Fix.day(2026, 11, 20), Fix.day(2027, 6, 20)]) == [599, 599])
        #expect(repository.posted(for: plan.id).map(\.amount) == [499, 499, 499])
    }

    @Test("A change back to the item's own value leaves the occurrence with no record of its own")
    func editBackClearsTheRecord() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 11, 20))
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .thisOccurrence) {
            $0.amount = 26_000
        }
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), scope: .thisOccurrence) {
            $0.amount = 25_000
        }
        #expect(try stored(rent.id, repository).occurrence(on: Fix.day(2026, 12, 1)) == nil)
    }

    @Test("D336.1: a start edit keeps an overdue occurrence's own values, on its old day")
    func ruleChangeKeepsOverdueEdits() throws {
        let rent = Fix.rent(automatic: false)
        let repository = try scene(rent, today: Fix.day(2026, 10, 20))
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 9, 1), scope: .thisOccurrence) {
            $0.amount = 20_000
        }
        try edit(rent.id, in: repository, occurrence: Fix.day(2026, 11, 1), scope: .allFuture) {
            $0.startDay = Fix.day(2026, 8, 5)
        }
        let board = try repository.useCases().listing().board
        #expect(board.overdue.map(\.day) == [Fix.day(2026, 8, 1), Fix.day(2026, 9, 1), Fix.day(2026, 10, 1)])
        #expect(board.overdue.map(\.occurrenceItem.amount) == [25_000, 20_000, 25_000])
        #expect(try next(rent.id, repository, count: 1).map(\.day) == [Fix.day(2026, 11, 5)])
    }

    @Test("A one-off item saves as a whole, with no occurrence of its own")
    func oneOffSavesWhole() throws {
        let fee = Fix.rent(amount: 900, start: Fix.day(2026, 11, 1), rule: .never, automatic: false)
        let repository = try scene(fee, today: Fix.day(2026, 10, 20))
        try edit(fee.id, in: repository, occurrence: Fix.day(2026, 11, 1), scope: .thisOccurrence) { $0.amount = 950 }
        let item = try stored(fee.id, repository)
        #expect(item.amount == 950)
        #expect(item.occurrences.isEmpty)
    }

    @Test("Changed fields leave out the SERIES fields, the type and the toggles")
    func changedFieldsAreNonSeries() {
        let rent = Fix.rent()
        var edited = rent
        edited.endDay = Fix.day(2027, 1, 1)
        edited.startDay = Fix.day(2026, 8, 3)
        edited.processesAutomatically = false
        let day = Fix.day(2026, 11, 1)
        #expect(
            ScheduledOccurrenceEdit.changedFields(shown: rent, shownDay: day, edited: edited, editedDay: day).isEmpty
        )
        edited.amount = 1
        edited.note = "Late"
        #expect(
            ScheduledOccurrenceEdit.changedFields(
                shown: rent,
                shownDay: day,
                edited: edited,
                editedDay: Fix.day(2026, 11, 2),
            )
                == [.day, .amount, .note]
        )
    }
}

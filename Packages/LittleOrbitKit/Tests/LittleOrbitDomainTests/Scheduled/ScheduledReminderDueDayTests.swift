import Foundation
import LittleOrbitDomain
import Testing

/// Reminders are chosen and capped by the day each occurrence is due, not by its key (#317, D428.4): an occurrence
/// "This occurrence only" moved earlier from beyond the planning window is reminded, one moved later out of it
/// isn't, and with the cap reached the nearest due days win. Identifiers still come from the key (#202). Made-up
/// data in `Asia/Kolkata`; today is Wed 28 Oct 2026, 08:00.
@Suite("Scheduled reminders by due day (#317, D428.4)")
struct ScheduledReminderDueDayTests {
    private typealias Fix = ScheduledFixture
    private static let kolkata = TimeZone(identifier: Fix.zone)!
    private static let now = Fix.date(2026, 10, 28, 8)
    private static let budget = ScheduledReminderPlanner.pendingBudget

    /// Phone Plan, ₹199 weekly on Mondays from 6 Jul, with 'Notify when due' on.
    private func phonePlan(automatic: Bool = false) -> ScheduledItem {
        var item = Fix.rent(amount: 199, start: Fix.day(2026, 7, 6), rule: .weekly, automatic: automatic)
        item.details = "Phone Plan"
        item.notifiesWhenDue = true
        return item
    }

    /// Electricity, ₹2,500 monthly on the 15th from 15 Aug, with 'Notify when due' on.
    private func electricity() -> ScheduledItem {
        var item = Fix.rent(amount: 2_500, start: Fix.day(2026, 8, 15), automatic: false)
        item.details = "Electricity"
        item.notifiesWhenDue = true
        return item
    }

    /// Mon 2 Nov 2026 plus `weeks` weeks: Phone Plan's occurrence that many weeks after its next one.
    private func monday(_ weeks: Int) -> CalendarDay {
        ScheduleCalendar.occurrence(weeks, from: Fix.day(2026, 11, 2), repeating: .weekly)!
    }

    /// The occurrence `key` moved to `day` with "This occurrence only", recorded as `outcome`.
    private func moved(
        _ item: ScheduledItem,
        _ key: CalendarDay,
        to day: CalendarDay,
        outcome: ScheduledOutcome = .edited,
        automatically: Bool? = nil,
    ) -> ScheduledItem {
        var item = item
        var edit = ScheduledOccurrenceEdit()
        edit.set(.day, from: item, day: day)
        item.occurrences.append(
            ScheduledOccurrence(
                id: ScheduledKey.occurrenceID(item: item.id, day: key),
                day: key,
                outcome: outcome,
                recordedAutomatically: automatically,
                edit: edit,
                createdAt: Fix.created,
            )
        )
        return item
    }

    private func plan(
        _ items: [ScheduledItem],
        now: Date = now,
        limit: Int = budget,
    ) -> [ScheduledReminder] {
        ScheduledReminderPlanner.plan(items, now: now, timeZone: Self.kolkata, time: .standard, limit: limit)
    }

    /// What a request is made of, without the item, whose records the move changes.
    private func requests(_ reminders: some Sequence<ScheduledReminder>) -> [String] {
        reminders.map { "\($0.id) \($0.day) \($0.fireDate.timeIntervalSince1970)" }
    }

    private func id(_ item: ScheduledItem, _ key: CalendarDay) -> String {
        ScheduledReminder.identifier(item: item.id, day: key)
    }

    @Test("Check 1: the occurrence 70 weeks out, moved to Mon 2 Nov, is reminded on 2 Nov at 09:00, by its own key")
    func movedEarlierFromBeyondTheWindow() {
        let item = phonePlan()
        let far = monday(70)
        let reminders = plan([moved(item, far, to: Fix.day(2026, 11, 2))])
        let reminder = reminders.first { $0.key == far }
        #expect(reminder?.day == Fix.day(2026, 11, 2))
        #expect(reminder?.fireDate == Fix.date(2026, 11, 2, 9))
        #expect(reminder?.id == id(item, far))
        // The nearest 60 due days: the moved one and the first 59 Mondays.
        #expect(reminders.count == Self.budget)
        #expect(reminders.filter { $0.key != far }.map(\.day) == (0..<(Self.budget - 1)).map(monday))
    }

    @Test("Check 2: with the cap reached across items, the nearest due days are planned and the latest is left out")
    func capKeepsTheNearestDueDays() {
        let phone = phonePlan()
        let bill = electricity()
        let before = plan([phone, bill])
        #expect(before.count == Self.budget)
        // Its key is the 61st Monday: inside the rule's window, after 60 other keys, so the cut by key dropped it.
        let later = monday(60)
        let after = plan([moved(phone, later, to: Fix.day(2026, 11, 3)), bill])
        #expect(after.count == Self.budget)
        // After Mon 2 Nov's, ahead of every later one.
        #expect(after.map(\.day).prefix(2) == [Fix.day(2026, 11, 2), Fix.day(2026, 11, 3)])
        #expect(after[1].id == id(phone, later))
        // Every other reminder is the same as before, in the same order, less the latest-due one.
        #expect(requests(after.filter { $0.id != id(phone, later) }) == requests(before.dropLast()))
        #expect(!after.map(\.id).contains(before.last!.id))
    }

    @Test("Check 2 for one item: a moved occurrence keyed after the first 60 still beats later due days")
    func capKeepsTheNearestForOneItem() {
        let item = phonePlan()
        let later = monday(60)
        let reminders = plan([moved(item, later, to: Fix.day(2026, 11, 4))])
        #expect(reminders.map(\.key) == [monday(0), later] + (1..<(Self.budget - 1)).map(monday))
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
    }

    @Test("Check 3: paying the moved occurrence removes only its reminder; the others keep theirs")
    func payingTheMovedOneDropsOnlyIt() {
        let item = phonePlan()
        let far = monday(70)
        let monday2Nov = Fix.date(2026, 11, 2, 8)
        let before = plan([moved(item, far, to: Fix.day(2026, 11, 2))], now: monday2Nov)
        #expect(before.contains { $0.id == id(item, far) })
        let paid = plan([moved(item, far, to: Fix.day(2026, 11, 2), outcome: .posted)], now: monday2Nov)
        #expect(!paid.contains { $0.id == id(item, far) })
        // The freed slot goes to the next Monday; every other identifier, day and time is unchanged.
        #expect(requests(paid.dropLast()) == requests(before.filter { $0.id != id(item, far) }))
        #expect(paid.last?.key == monday(Self.budget - 1))
    }

    @Test("Check 4: the occurrence next week moved 70 weeks later isn't reminded next week, then is once it's near")
    func movedLaterOutOfTheWindow() {
        let item = phonePlan()
        let next = monday(0)
        let item70 = moved(item, next, to: monday(70))
        let reminders = plan([item70])
        #expect(!reminders.contains { $0.day == next || $0.key == next })
        #expect(reminders.map(\.day) == (1...Self.budget).map(monday))
        // 20 weeks before its new day, it's among the nearest 60, by its own key's identifier.
        let near = plan([item70], now: Fix.date(2027, 10, 18, 8))
        let reminder = near.first { $0.key == next }
        #expect(reminder?.day == monday(70))
        #expect(reminder?.id == id(item, next))
        #expect(near.count == Self.budget)
    }

    @Test("Check 5: with nothing moved, the planned identifiers, days and order are the nearest 60 as before")
    func unmovedKeepTheirIdentifiersAndOrder() {
        let phone = phonePlan()
        var bill = electricity()
        bill.occurrences.append(
            ScheduledOccurrence(
                id: ScheduledKey.occurrenceID(item: bill.id, day: Fix.day(2026, 12, 15)),
                day: Fix.day(2026, 12, 15),
                outcome: .skipped,
                createdAt: Fix.created,
            )
        )
        let reminders = plan([phone, bill])
        // Worked out apart from the planner: every Monday and every 15th but 15 Dec, nearest first.
        let mondays = (0..<Self.budget).map { (key: monday($0), item: phone) }
        let fifteenths = (0..<Self.budget)
            .compactMap { index -> (key: CalendarDay, item: ScheduledItem)? in
                let day = ScheduleCalendar.occurrence(index, from: Fix.day(2026, 11, 15), repeating: .monthly)!
                return day == Fix.day(2026, 12, 15) ? nil : (key: day, item: bill)
            }
        // Mon 15 Feb, Mon 15 Mar and Mon 15 Nov 2027 have one of each, ordered by identifier.
        let expected = (mondays + fifteenths)
            .sorted { $0.key == $1.key ? id($0.item, $0.key) < id($1.item, $1.key) : $0.key < $1.key }
            .prefix(Self.budget)
        #expect(reminders.map(\.id) == expected.map { id($0.item, $0.key) })
        #expect(reminders.map(\.day) == expected.map(\.key))
        #expect(reminders.allSatisfy { $0.key == $0.day })
    }

    @Test("An automatic occurrence keyed 70 weeks out, moved to today and recorded by the app, keeps today's 09:00")
    func recordedAutomaticallyOnItsMovedDay() {
        let item = phonePlan(automatic: true)
        let far = monday(70)
        let today = Fix.day(2026, 10, 28)
        let reminders = plan([moved(item, far, to: today, outcome: .posted, automatically: true)])
        #expect(reminders.first?.id == id(item, far))
        #expect(reminders.first?.fireDate == Fix.date(2026, 10, 28, 9))
        // Paid by the user instead, it gets none (D354.1).
        let paid = plan([moved(item, far, to: today, outcome: .posted)])
        #expect(!paid.contains { $0.key == far })
    }

    @Test("D435: a move whose own day a Starts edit took off the rule is kept, so it's reminded on its moved day")
    func keptMoveIsReminded() throws {
        // Tue 20 Oct: Mon 26 Oct is moved to Fri 30 Oct. Wed 21 Oct: Starts becomes Tue 27 Oct, so 26 Oct is no
        // longer on the rule. The board shows it and Pay accepts it (D435.1), so its reminder follows them.
        var snapshot = try LedgerBook.savingScheduledItem(
            phonePlan(),
            in: Fix.ledger,
            today: Fix.day(2026, 7, 1),
            now: Fix.created,
        )
        let key = Fix.day(2026, 10, 26)
        let save = ScheduledOccurrenceSave(occurrence: key, dueDay: Fix.day(2026, 10, 30), scope: .thisOccurrence)
        snapshot = try LedgerBook.savingScheduledOccurrence(
            snapshot.scheduledItems[0],
            editing: save,
            in: snapshot,
            today: Fix.day(2026, 10, 20),
            now: Fix.date(2026, 10, 20),
        )
        var tuesdays = snapshot.scheduledItems[0]
        tuesdays.startDay = Fix.day(2026, 10, 27)
        snapshot = try LedgerBook.savingScheduledItem(
            tuesdays,
            in: snapshot,
            today: Fix.day(2026, 10, 21),
            now: Fix.date(2026, 10, 21),
        )
        let item = snapshot.scheduledItems[0]
        #expect(item.occurrence(on: key)?.outcome == .pending)
        let board = ScheduledBoard.make(snapshot, today: Fix.day(2026, 10, 30))
        #expect(board.dueToday.contains { $0.key == key && $0.day == Fix.day(2026, 10, 30) })
        let reminders = plan([item])
        #expect(reminders.first?.id == id(item, key))
        #expect(reminders.first?.fireDate == Fix.date(2026, 10, 30, 9))
        #expect(reminders.dropFirst().first?.day == Fix.day(2026, 11, 3))
    }
}

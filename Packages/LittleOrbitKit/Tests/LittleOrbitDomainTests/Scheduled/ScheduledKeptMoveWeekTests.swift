import Foundation
import LittleOrbitDomain
import Testing

/// Second-lander pins for #316 on #202 (D437, D442.3, Tech Architect's review 5690774452). A kept "This occurrence
/// only" move holds the one ISO week (Monday first) of the current rule that holds its due day, so no new-rule
/// payment is due or recorded in that week, through catch-up too. A removed or orphaned edited occurrence holds no
/// period, so the rule's own occurrence there is due as normal. Made-up data: Phone Plan ₹199 weekly, from Everyday
/// Savings, with Mon 26 Oct moved to Wed 4 Nov and Starts then changed to Tue 27 Oct.
@MainActor
@Suite("A kept move's week, catch-up, and removed occurrences (D437, D442.3)")
struct ScheduledKeptMoveWeekTests {
    private typealias Fix = ScheduledFixture

    /// Phone Plan weekly from Tue 27 Oct, with 26 Oct kept pending on 4 Nov (D435).
    private static func phone(automatic: Bool = false) -> ScheduledItem {
        var item = Fix.rent(amount: 199, start: Fix.day(2026, 10, 27), rule: .weekly, automatic: automatic)
        var edit = ScheduledOccurrenceEdit()
        edit.set(.day, from: item, day: Fix.day(2026, 11, 4))
        let kept = ScheduledOccurrence(
            id: UUID(),
            day: Fix.day(2026, 10, 26),
            outcome: .pending,
            edit: edit,
            createdAt: Fix.created,
        )
        item.occurrences = [kept]
        return item
    }

    /// The ISO week (Monday first) that holds `day`, as a count of weeks from 1 Jan 2026 (a Thursday).
    private static func week(of day: CalendarDay) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let origin = calendar.date(from: DateComponents(year: 2025, month: 12, day: 29))!
        let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))!
        let days = calendar.dateComponents([.day], from: origin, to: date).day!
        return days >= 0 ? days / 7 : (days - 6) / 7
    }

    @Test("3 Nov and 4 Nov never share a week: 27 Oct is due, 4 Nov holds 2–8 Nov, and each week has one payment")
    func threeAndFourNovemberNeverShareAWeek() {
        let phone = Self.phone()
        let due = ScheduleCalendar.dueOccurrences(of: phone, through: Fix.day(2026, 11, 30)).map(\.day)
        #expect(due.contains(Fix.day(2026, 10, 27)), "\(due)")
        #expect(due.contains(Fix.day(2026, 11, 4)), "\(due)")
        #expect(!due.contains(Fix.day(2026, 11, 3)), "\(due)")
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 3), of: phone))
        #expect(Self.week(of: Fix.day(2026, 11, 3)) == Self.week(of: Fix.day(2026, 11, 4)))
        let weeks = due.map(Self.week(of:))
        #expect(Set(weeks).count == weeks.count, "\(due)")
    }

    @Test("No new-rule payment lands in a kept move's week, through catch-up: 27 Oct, 4 Nov and 10 Nov, once each")
    func catchUpRecordsNothingElseInTheKeptMovesWeek() throws {
        let phone = Self.phone(automatic: true)
        var ledger = Fix.ledger
        ledger.scheduledItems = [phone]
        var snapshot = ledger
        for today in [Fix.day(2026, 10, 28), Fix.day(2026, 11, 4), Fix.day(2026, 11, 12), Fix.day(2026, 11, 12)] {
            let caught = LedgerBook.catchingUpScheduledItems(
                in: snapshot,
                today: today,
                now: Fix.date(today.year, today.month, today.day),
            )
            snapshot = caught.snapshot
        }
        let posted = snapshot.transactions.filter { $0.scheduledTemplateID == phone.id }
        let days = posted.compactMap(TransactionCalendar.calendarDay(of:)).sorted()
        #expect(days == [Fix.day(2026, 10, 27), Fix.day(2026, 11, 4), Fix.day(2026, 11, 10)])
        let ids = Set(posted.map(\.id))
        #expect(ids.contains(ScheduledKey.transactionID(item: phone.id, day: Fix.day(2026, 10, 26))))
        #expect(!ids.contains(ScheduledKey.transactionID(item: phone.id, day: Fix.day(2026, 11, 3))))
        let weeks = days.map(Self.week(of:))
        #expect(Set(weeks).count == weeks.count, "\(days)")
    }

    @Test("D442.3: a removed occurrence takes no period, so Tue 3 Nov is created as normal in its week")
    func removedOccurrenceTakesNoPeriod() {
        var phone = Fix.rent(amount: 199, start: Fix.day(2026, 10, 27), rule: .weekly, automatic: false)
        var edit = ScheduledOccurrenceEdit()
        edit.set(.day, from: phone, day: Fix.day(2026, 11, 4))
        let removed = ScheduledOccurrence(
            id: UUID(),
            day: Fix.day(2026, 10, 26),
            outcome: .pending,
            edit: edit,
            createdAt: Fix.created,
            deletedAt: Fix.date(2026, 10, 21),
        )
        phone.occurrences = [removed]
        let due = ScheduleCalendar.dueOccurrences(of: phone, through: Fix.day(2026, 11, 10)).map(\.day)
        #expect(due == [Fix.day(2026, 10, 27), Fix.day(2026, 11, 3), Fix.day(2026, 11, 10)])
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 3), of: phone))
    }

    @Test("D442.3 check C: 26 Oct edited to ₹249, Starts changed to Tue 27 Oct: 27 Oct is created at ₹199")
    func editedOccurrenceOffTheRuleTakesNoPeriod() throws {
        let phone = Fix.rent(amount: 199, start: Fix.day(2026, 10, 5), rule: .weekly, automatic: false)
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        try repository.useCases().save(phone)
        repository.now = Fix.date(2026, 10, 21)
        let key = Fix.day(2026, 10, 26)
        let current = try #require(repository.snapshot.scheduledItems.first)
        var form = current.resolved(for: key)
        form.occurrences = current.occurrences
        form.amount = 249
        _ = try repository.useCases()
            .update(
                form,
                editing: ScheduledOccurrenceSave(occurrence: key, dueDay: key, scope: .thisOccurrence),
                payee: nil,
            )
        var edited = try #require(repository.snapshot.scheduledItems.first)
        edited.startDay = Fix.day(2026, 10, 27)
        try repository.useCases().save(edited)
        let item = try #require(repository.snapshot.scheduledItems.first)
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 3)).map(\.day)
        #expect(due.contains(Fix.day(2026, 10, 27)), "\(due)")
        #expect(!due.contains(key), "\(due)")
        #expect(item.resolved(for: Fix.day(2026, 10, 27)).amount == 199)
    }
}

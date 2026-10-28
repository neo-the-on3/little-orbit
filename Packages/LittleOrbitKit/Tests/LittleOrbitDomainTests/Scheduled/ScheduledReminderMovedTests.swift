import Foundation
import LittleOrbitDomain
import Testing

/// 'Notify when due' for an occurrence with its own values (#204 with #202, D45): its reminder arrives on the day it
/// moved to, once, with the old day's reminder gone because it keeps the occurrence's identifier, and its content
/// reads the occurrence's own values. Made-up data in `Asia/Kolkata`; today is 20 Oct 2026.
@Suite("Scheduled reminders for a moved occurrence (#204, D45)")
struct ScheduledReminderMovedTests {
    private typealias Fix = ScheduledFixture
    private static let kolkata = TimeZone(identifier: Fix.zone)!

    /// Electricity, ₹25,000 monthly on the 15th from 15 Aug, with 'Notify when due' on.
    private func electricity() -> ScheduledItem {
        var item = Fix.rent(start: Fix.day(2026, 8, 15), automatic: false)
        item.details = "Electricity"
        item.notifiesWhenDue = true
        return item
    }

    private func moved(
        _ item: ScheduledItem,
        _ key: CalendarDay,
        to day: CalendarDay,
        amount: Decimal,
    ) -> ScheduledItem {
        var item = item
        var edit = ScheduledOccurrenceEdit()
        var source = item
        source.amount = amount
        edit.set(.day, from: source, day: day)
        edit.set(.amount, from: source, day: day)
        item.occurrences.append(
            ScheduledOccurrence(
                id: ScheduledKey.occurrenceID(item: item.id, day: key),
                day: key,
                outcome: .edited,
                edit: edit,
                createdAt: Fix.created,
            )
        )
        return item
    }

    private func plan(_ items: [ScheduledItem], limit: Int = 3) -> [ScheduledReminder] {
        ScheduledReminderPlanner.plan(
            items,
            now: Fix.date(2026, 10, 20, 8),
            timeZone: Self.kolkata,
            time: .standard,
            limit: limit,
        )
    }

    @Test("15 Nov moved to 18 Nov at ₹26,000: reminded on 18 Nov at 09:00, by 15 Nov's identifier, with ₹26,000")
    func movedLater() {
        let item = electricity()
        let november = Fix.day(2026, 11, 15)
        let reminders = plan([moved(item, november, to: Fix.day(2026, 11, 18), amount: 26_000)])
        #expect(reminders.map(\.day) == [Fix.day(2026, 11, 18), Fix.day(2026, 12, 15), Fix.day(2027, 1, 15)])
        #expect(reminders.first?.fireDate == Fix.date(2026, 11, 18, 9))
        #expect(reminders.first?.id == ScheduledReminder.identifier(item: item.id, day: november))
        #expect(reminders.first?.key == november)
        #expect(reminders.first?.item.amount == 26_000)
        #expect(reminders.dropFirst().allSatisfy { $0.item.amount == 25_000 })
    }

    @Test("15 Oct, already past, moved to 22 Oct: reminded on 22 Oct, once")
    func pastKeyMovedAhead() {
        let item = electricity()
        let october = Fix.day(2026, 10, 15)
        let reminders = plan([moved(item, october, to: Fix.day(2026, 10, 22), amount: 25_500)])
        #expect(reminders.map(\.day) == [Fix.day(2026, 10, 22), Fix.day(2026, 11, 15), Fix.day(2026, 12, 15)])
        #expect(reminders.first?.id == ScheduledReminder.identifier(item: item.id, day: october))
        #expect(Set(reminders.map(\.id)).count == 3)
    }

    @Test("15 Nov moved back to 19 Oct, already past: no reminder for it")
    func movedIntoThePast() {
        let item = electricity()
        let reminders = plan([moved(item, Fix.day(2026, 11, 15), to: Fix.day(2026, 10, 19), amount: 25_000)])
        #expect(reminders.map(\.day) == [Fix.day(2026, 12, 15), Fix.day(2027, 1, 15), Fix.day(2027, 2, 15)])
    }
}

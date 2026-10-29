import Foundation
import LittleOrbitDomain
import Testing

/// The reminder use cases against `FakeNotificationScheduling`, the fake of the system's notifications behind the
/// port the App's adapter implements (#26, D340.7; Tech Architect on #204). Each test reads what the fake was asked
/// to schedule: identifiers, fire dates and content. Made-up data in `Asia/Kolkata`; now is 20 Oct 2026, 08:00.
@MainActor
@Suite("Scheduled reminders through the fake notification adapter (#26, D340.7)")
struct ScheduledReminderNotificationTests {
    private typealias Fix = ScheduledFixture

    private let repository = FakeScheduleRepository()
    private let notifications = FakeNotificationScheduling()

    private var reminders: DefaultScheduledReminderUseCases {
        DefaultScheduledReminderUseCases(
            repository: repository,
            notifications: notifications,
            times: InMemoryScheduledReminderTimeStore(),
            wording: EchoReminderWording(),
            now: { [repository] in repository.now },
            timeZone: { TimeZone(identifier: Fix.zone)! },
        )
    }

    /// A notified manual item, saved, with now moved to 20 Oct 2026, 08:00.
    @discardableResult
    private func saved(
        _ details: String,
        start: CalendarDay,
        rule: ScheduleRepeat = .monthly,
        end: CalendarDay? = Fix.day(2026, 12, 31),
    ) throws -> ScheduledItem {
        var item = Fix.rent(start: start, rule: rule, end: end, automatic: false)
        item.details = details
        item.notifiesWhenDue = true
        repository.now = Fix.created
        try repository.useCases().save(item)
        repository.now = Fix.date(2026, 10, 20, 8)
        return item
    }

    private func identifiers(_ item: ScheduledItem, _ days: [CalendarDay]) -> Set<String> {
        Set(days.map { ScheduledReminder.identifier(item: item.id, day: $0) })
    }

    @Test("Schedules every pending reminder with its identifier, fire date and content")
    func schedulesPending() async throws {
        let item = try saved("Electricity", start: Fix.day(2026, 8, 20))
        try await reminders.reschedule()
        let days = [Fix.day(2026, 10, 20), Fix.day(2026, 11, 20), Fix.day(2026, 12, 20)]
        #expect(Set(notifications.pending.keys) == identifiers(item, days))
        #expect(notifications.fireDates == days.map { Fix.date($0.year, $0.month, $0.day, 9) })
        #expect(
            notifications.pending.values.allSatisfy {
                $0.itemID == item.id
                    && $0.content
                        == ScheduledNotificationContent(title: "Electricity", body: "manual Everyday Savings")
            }
        )
        #expect(notifications.added.count == 1)
    }

    /// D428.2 (superseding D338.8): the edit is saved on 20 Oct, when 20 Oct is due, so 20 Oct is kept and October
    /// has its occurrence; the new rule's reminders start on 25 Nov.
    @Test("An edit replaces the item's reminders: the old dates go, the new ones arrive with the new words")
    func editReplaces() async throws {
        var item = try saved("Electricity", start: Fix.day(2026, 8, 20))
        try await reminders.reschedule()
        let before = Set(notifications.pending.keys)

        item.details = "Power"
        item.startDay = Fix.day(2026, 8, 25)
        try repository.useCases().save(item)
        try await reminders.reschedule()

        let days = [Fix.day(2026, 10, 20), Fix.day(2026, 11, 25), Fix.day(2026, 12, 25)]
        let kept = identifiers(item, [Fix.day(2026, 10, 20)])
        #expect(Set(notifications.pending.keys) == identifiers(item, days))
        #expect(before.intersection(notifications.pending.keys) == kept)
        #expect(Set(notifications.removed.flatMap { $0 }) == before.subtracting(kept))
        #expect(notifications.fireDates == days.map { Fix.date($0.year, $0.month, $0.day, 9) })
        #expect(notifications.pending.values.allSatisfy { $0.content.title == "Power" })
    }

    @Test("A reschedule with nothing changed asks again for the same identifiers, so nothing is duplicated")
    func rescheduleIsIdempotent() async throws {
        _ = try saved("Electricity", start: Fix.day(2026, 8, 20))
        try await reminders.reschedule()
        try await reminders.reschedule()
        #expect(notifications.added.count == 2)
        #expect(notifications.added[0] == notifications.added[1])
        #expect(notifications.pending.count == 3)
        #expect(notifications.removed.isEmpty)
    }

    @Test("Pay removes that occurrence's reminder and keeps the rest")
    func payRemoves() async throws {
        let item = try saved("Electricity", start: Fix.day(2026, 8, 20))
        try await reminders.reschedule()
        try repository.useCases().payNow(itemID: item.id, occurrence: Fix.day(2026, 10, 20))
        try await reminders.reschedule()
        #expect(
            notifications.removed.last == [ScheduledReminder.identifier(item: item.id, day: Fix.day(2026, 10, 20))]
        )
        #expect(
            Set(notifications.pending.keys) == identifiers(item, [Fix.day(2026, 11, 20), Fix.day(2026, 12, 20)])
        )
    }

    @Test("Skip removes that occurrence's reminder and keeps the rest")
    func skipRemoves() async throws {
        let item = try saved("Electricity", start: Fix.day(2026, 8, 20))
        try await reminders.reschedule()
        try repository.useCases().skip(itemID: item.id, occurrence: Fix.day(2026, 11, 20))
        try await reminders.reschedule()
        #expect(
            notifications.removed.last == [ScheduledReminder.identifier(item: item.id, day: Fix.day(2026, 11, 20))]
        )
        #expect(
            Set(notifications.pending.keys) == identifiers(item, [Fix.day(2026, 10, 20), Fix.day(2026, 12, 20)])
        )
    }

    @Test("Deleting the item removes all of its reminders and leaves another item's")
    func deleteRemoves() async throws {
        let item = try saved("Electricity", start: Fix.day(2026, 8, 20))
        let other = try saved("Water", start: Fix.day(2026, 8, 28))
        try await reminders.reschedule()
        try repository.useCases().delete(id: item.id)
        try await reminders.reschedule()
        let gone = identifiers(item, [Fix.day(2026, 10, 20), Fix.day(2026, 11, 20), Fix.day(2026, 12, 20)])
        #expect(Set(notifications.removed.last ?? []) == gone)
        #expect(notifications.pending.values.allSatisfy { $0.itemID == other.id })
        #expect(notifications.pending.count == 3)
    }

    @Test("One budget of 60 across items: a near weekly item and a far monthly one, earliest dates first")
    func sharedBudget() async throws {
        let weekly = try saved("Groceries", start: Fix.day(2026, 8, 20), rule: .weekly, end: nil)
        let monthly = try saved("Rent", start: Fix.day(2027, 3, 1), end: nil)
        try await reminders.reschedule()

        #expect(notifications.pending.count == ScheduledReminderPlanner.pendingBudget)
        #expect(notifications.pending.count < ScheduledReminderPlanner.systemPendingLimit)
        let byItem = Dictionary(grouping: notifications.pending.values, by: \.itemID)
        let weeklyDays = (byItem[weekly.id] ?? []).map(\.day).sorted()
        let monthlyDays = (byItem[monthly.id] ?? []).map(\.day).sorted()
        // The monthly item starts in March 2027, so the weekly one takes every slot before then, and the monthly
        // item gets its 1st-of-the-month dates only up to the 60th date overall.
        #expect(weeklyDays.first == Fix.day(2026, 10, 22))
        #expect(monthlyDays.first == Fix.day(2027, 3, 1))
        #expect(!monthlyDays.isEmpty && weeklyDays.count > monthlyDays.count)
        let last = try #require(notifications.fireDates.last)
        let all = ScheduledReminderPlanner.plan(
            [weekly, monthly],
            now: repository.now,
            timeZone: TimeZone(identifier: Fix.zone)!,
            time: .standard,
            limit: 10_000,
        )
        let kept = Set(notifications.pending.keys)
        #expect(all.filter { !kept.contains($0.id) }.allSatisfy { $0.fireDate >= last })
        #expect(Set(all.filter { $0.fireDate <= last }.map(\.id)) == kept)
    }
}

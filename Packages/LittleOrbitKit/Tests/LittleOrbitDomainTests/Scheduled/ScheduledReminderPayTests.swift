import Foundation
import LittleOrbitDomain
import Testing

/// D354.1: an occurrence the app records keeps its reminder (S81); the user's Pay or Skip leaves no reminder, and
/// the planner itself leaves it out, so no reschedule or Redo adds it back. An Undo brings it back only while its
/// time is still ahead. Made-up data in `Asia/Kolkata`; today is 20 Oct 2026, 08:00.
@MainActor
@Suite("Scheduled reminders after Pay and Skip (#26, D354.1)")
struct ScheduledReminderPayTests {
    private typealias Fix = ScheduledFixture

    private let repository = FakeScheduleRepository()
    private let notifications = FakeNotificationScheduling()
    private let today = ScheduledFixture.day(2026, 10, 20)

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

    private func electricity(day: Int = 20, automatic: Bool) throws -> ScheduledItem {
        var item = Fix.rent(start: Fix.day(2026, 8, day), end: Fix.day(2026, 12, 31), automatic: automatic)
        item.details = "Electricity"
        item.notifiesWhenDue = true
        repository.now = Fix.created
        try repository.useCases().save(item)
        repository.now = Fix.date(2026, 10, 20, 8)
        return item
    }

    private func pending(_ item: ScheduledItem, _ day: CalendarDay) -> Bool {
        notifications.pending[ScheduledReminder.identifier(item: item.id, day: day)] != nil
    }

    private func record(_ item: ScheduledItem, _ day: CalendarDay) -> ScheduledOccurrence? {
        repository.snapshot.scheduledItems.first { $0.id == item.id }?.occurrence(on: day)
    }

    @Test("The app recording an automatic occurrence on its due day keeps its 09:00 reminder")
    func appRecordingKeepsIt() async throws {
        let item = try electricity(automatic: true)
        try await reminders.reschedule()
        #expect(pending(item, today))
        #expect(try repository.useCases().catchUp(atLaunch: false).changedLedger)
        #expect(record(item, today)?.recordedAutomatically == true)
        try await reminders.reschedule()
        #expect(pending(item, today))
    }

    @Test("A manual Pay Now at 08:00 on an automatic item's due day drops the 09:00 reminder, for good")
    func payAtEightDropsNine() async throws {
        let item = try electricity(automatic: true)
        try await reminders.reschedule()
        #expect(pending(item, today))
        try repository.useCases().payNow(itemID: item.id, occurrence: today)
        #expect(record(item, today)?.recordedAutomatically == nil)
        try await reminders.reschedule()
        #expect(!pending(item, today))
        // Another reschedule, at activation, or a catch-up afterwards, doesn't add it back.
        _ = try repository.useCases().catchUp(atLaunch: true)
        try await reminders.reschedule()
        try await reminders.reschedule()
        #expect(!pending(item, today))
        #expect(notifications.days == [Fix.day(2026, 11, 20), Fix.day(2026, 12, 20)])
    }

    @Test("Paying an automatic item's next occurrence early drops that reminder")
    func payAutomaticEarly() async throws {
        let item = try electricity(automatic: true)
        _ = try repository.useCases().catchUp(atLaunch: true)
        try repository.useCases().payNow(itemID: item.id, occurrence: Fix.day(2026, 11, 20))
        try await reminders.reschedule()
        #expect(notifications.days == [today, Fix.day(2026, 12, 20)])
    }

    @Test("Pay and Skip on a manual item, and Skip on an automatic one, drop the reminder")
    func manualPayAndSkips() async throws {
        let bill = try electricity(automatic: false)
        let rent = try electricity(day: 21, automatic: true)
        try await reminders.reschedule()
        try repository.useCases().payNow(itemID: bill.id, occurrence: today)
        try repository.useCases().skip(itemID: rent.id, occurrence: Fix.day(2026, 10, 21))
        try await reminders.reschedule()
        #expect(!pending(bill, today))
        #expect(!pending(rent, Fix.day(2026, 10, 21)))
        #expect(pending(rent, Fix.day(2026, 11, 21)))
    }

    @Test("Undo of a Pay or Skip brings the reminder back while it's ahead, and Redo drops it again")
    func undoAndRedo() async throws {
        let item = try electricity(automatic: true)
        let before = repository.snapshot
        try await reminders.reschedule()
        try repository.useCases().payNow(itemID: item.id, occurrence: today)
        let paid = repository.snapshot
        try await reminders.reschedule()
        #expect(!pending(item, today))
        repository.snapshot = before  // Undo
        try await reminders.reschedule()
        #expect(pending(item, today))
        repository.snapshot = paid  // Redo
        try await reminders.reschedule()
        #expect(!pending(item, today))

        repository.snapshot = before
        try repository.useCases().skip(itemID: item.id, occurrence: today)
        try await reminders.reschedule()
        #expect(!pending(item, today))
        repository.snapshot = before  // Undo
        try await reminders.reschedule()
        #expect(pending(item, today))
    }

    @Test("Undo after the reminder's time has passed doesn't bring it back")
    func undoAfterTimePassed() async throws {
        let item = try electricity(automatic: false)
        let before = repository.snapshot
        try await reminders.reschedule()
        try repository.useCases().payNow(itemID: item.id, occurrence: today)
        try await reminders.reschedule()
        repository.now = Fix.date(2026, 10, 20, 10)
        repository.snapshot = before  // Undo, after 09:00
        try await reminders.reschedule()
        #expect(!pending(item, today))
        #expect(notifications.days == [Fix.day(2026, 11, 20), Fix.day(2026, 12, 20)])
    }
}

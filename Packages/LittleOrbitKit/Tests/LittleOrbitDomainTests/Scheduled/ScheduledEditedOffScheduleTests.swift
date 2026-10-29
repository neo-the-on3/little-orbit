import Foundation
import LittleOrbitDomain
import Testing

/// D442.2 (C): an occurrence with its own amount, not moved, whose own day a Starts edit takes off the rule is
/// removed, and the save reports it. Made-up data in `Asia/Kolkata`: Phone Plan, ₹199.00 weekly on Mondays from Mon 12
/// Oct 2026, from Everyday Savings (INR), with 12 and 19 Oct paid. On Tue 20 Oct Mon 26 Oct's amount becomes ₹249.00
/// for this occurrence only; on Wed 21 Oct Starts becomes Tue 27 Oct. Every save goes through the use cases.
@MainActor
@Suite("An edited occurrence a Starts edit takes off the rule (D442.2)")
struct ScheduledEditedOffScheduleTests {
    private typealias Fix = ScheduledFixture
    private static let kolkata = TimeZone(identifier: Fix.zone)!
    private static let key = Fix.day(2026, 10, 26)
    private static let tuesday = Fix.day(2026, 10, 27)

    private static func example(
        key: CalendarDay = Self.key,
        save: (inout ScheduledItem) -> Void = { $0.startDay = Self.tuesday },
    ) throws -> (repository: FakeScheduleRepository, change: ScheduledItemSaveChange) {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let useCases = repository.useCases()
        var phone = Fix.rent(amount: 199, start: Fix.day(2026, 10, 12), rule: .weekly, automatic: false)
        phone.details = "Phone Plan"
        phone.notifiesWhenDue = true
        let saved = try useCases.save(phone, payee: nil).after
        for day in [Fix.day(2026, 10, 12), Fix.day(2026, 10, 19)] {
            _ = try repository.settleScheduledOccurrence(.pay(itemID: saved.id, occurrence: day, postedOn: day))
        }
        repository.now = Fix.date(2026, 10, 20)
        var dearer = repository.snapshot.scheduledItems[0]
        dearer.amount = 249
        let edit = ScheduledOccurrenceSave(occurrence: key, dueDay: key, scope: .thisOccurrence)
        _ = try useCases.update(dearer, editing: edit, payee: nil)
        repository.now = Fix.date(2026, 10, 21)
        var changed = repository.snapshot.scheduledItems[0]
        save(&changed)
        let change = try useCases.update(changed, payee: nil)
        return (repository, change)
    }

    @Test("D442 (C): the ₹249.00 26 Oct edit is removed, reported, and Tue 27 Oct is due at ₹199.00")
    func editedOffTheRuleIsRemoved() throws {
        let (repository, change) = try Self.example()
        #expect(change.before?.occurrence(on: Self.key)?.edit?.amount == 249)
        #expect(change.removed == [.init(reason: .editedOffSchedule, key: Self.key, dueDay: Self.key)])
        let snapshot = repository.snapshot
        let item = snapshot.scheduledItems[0]
        #expect(item.occurrence(on: Self.key) == nil)
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 10))
        #expect(due.map(\.day) == [Self.tuesday, Fix.day(2026, 11, 3), Fix.day(2026, 11, 10)])
        #expect(item.resolved(for: Self.tuesday).amount == 199)
        #expect(ScheduledBoard.make(snapshot, today: Self.key).dueToday.isEmpty)
        let reminders = ScheduledReminderPlanner.plan(
            [item],
            now: Fix.date(2026, 10, 21),
            timeZone: Self.kolkata,
            time: .standard,
            limit: 3,
        )
        #expect(reminders.first?.id == ScheduledReminder.identifier(item: item.id, day: Self.tuesday))
        #expect(!reminders.contains { $0.id == ScheduledReminder.identifier(item: item.id, day: Self.key) })
        let paid = try LedgerBook.settlingScheduledOccurrence(
            .pay(itemID: item.id, occurrence: Self.tuesday, postedOn: Self.tuesday),
            in: snapshot,
            now: Fix.date(2026, 10, 27),
        )
        #expect(paid.transaction?.amount == 199)
    }

    @Test("D442 (C): Undo of the Starts save restores 26 Oct at ₹249.00, due, and Starts on 12 Oct")
    func undoRestoresTheRemovedEdit() throws {
        let (repository, change) = try Self.example()
        repository.now = Fix.date(2026, 10, 21, 11)
        guard case .reverted = try repository.revertScheduledItemSave(change, undone: false) else {
            Issue.record("Undo was stale")
            return
        }
        let item = repository.snapshot.scheduledItems[0]
        #expect(item.startDay == Fix.day(2026, 10, 12))
        #expect(item.occurrence(on: Self.key)?.outcome == .edited)
        #expect(item.resolved(for: Self.key).amount == 249)
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 10, 31))
        #expect(due.map(\.day) == [Self.key])
    }

    @Test("D442.2: an edit kept as pending before today stays due; only one from today on is removed")
    func overdueEditStaysPending() throws {
        // Undo, then on Wed 28 Oct, with 26 Oct still unpaid, Starts becomes Tue 27 Oct: 26 Oct is overdue, so it
        // stays due at ₹249.00 (D336.1).
        let (repository, first) = try Self.example()
        _ = try repository.revertScheduledItemSave(first, undone: false)
        repository.now = Fix.date(2026, 10, 28)
        var tuesdays = repository.snapshot.scheduledItems[0]
        tuesdays.startDay = Self.tuesday
        let change = try repository.useCases().update(tuesdays, payee: nil)
        #expect(change.removed.isEmpty)
        let item = repository.snapshot.scheduledItems[0]
        #expect(item.occurrence(on: Self.key)?.outcome == .pending)
        #expect(item.resolved(for: Self.key).amount == 249)
    }

    // MARK: D444.2: past an End date

    @Test("D444.2 (D): ₹249.00 on Mon 2 Nov, then End 31 Oct: 2 Nov is removed and reported; Undo restores it")
    func editedPastTheNewEndIsRemoved() throws {
        let november = Fix.day(2026, 11, 2)
        let (repository, change) = try Self.example(key: november) { $0.endDay = Fix.day(2026, 10, 31) }
        #expect(change.removed == [.init(reason: .editedOffSchedule, key: november, dueDay: november)])
        let item = repository.snapshot.scheduledItems[0]
        #expect(item.occurrence(on: november) == nil)
        #expect(ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 30)).map(\.day) == [Self.key])
        let reminders = ScheduledReminderPlanner.plan(
            [item],
            now: Fix.date(2026, 10, 21),
            timeZone: Self.kolkata,
            time: .standard,
            limit: 3,
        )
        #expect(!reminders.contains { $0.id == ScheduledReminder.identifier(item: item.id, day: november) })
        repository.now = Fix.date(2026, 10, 21, 11)
        guard case .reverted = try repository.revertScheduledItemSave(change, undone: false) else {
            Issue.record("Undo was stale")
            return
        }
        let restored = repository.snapshot.scheduledItems[0]
        #expect(restored.endDay == nil)
        #expect(restored.resolved(for: november).amount == 249)
        #expect(
            ScheduleCalendar.dueOccurrences(of: restored, through: Fix.day(2026, 11, 2)).map(\.day).contains(november)
        )
    }
}

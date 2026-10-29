import Foundation
import LittleOrbitDomain
import Testing

/// Which occurrences get a 'Notify when due' reminder, and when (#26 S9–S11, S23, S25, S81, D340.7). Made-up data
/// in `Asia/Kolkata`; today is 20 Oct 2026 unless a test says otherwise.
@Suite("Scheduled reminder planner (#26, D340.7)")
struct ScheduledReminderPlannerTests {
    private typealias Fix = ScheduledFixture
    private static let kolkata = TimeZone(identifier: Fix.zone)!

    private func electricity(
        day: Int = 15,
        rule: ScheduleRepeat = .monthly,
        automatic: Bool = false,
        notifies: Bool = true,
        end: CalendarDay? = nil,
    ) -> ScheduledItem {
        var item = Fix.rent(start: Fix.day(2026, 8, day), rule: rule, end: end, automatic: automatic)
        item.details = "Electricity"
        item.notifiesWhenDue = notifies
        return item
    }

    private func plan(
        _ items: [ScheduledItem],
        now: Date = Fix.date(2026, 10, 20, 8),
        zone: TimeZone = kolkata,
        time: ReminderTime = .standard,
        limit: Int = ScheduledReminderPlanner.pendingBudget,
    ) -> [ScheduledReminder] {
        ScheduledReminderPlanner.plan(items, now: now, timeZone: zone, time: time, limit: limit)
    }

    private func settled(
        _ item: ScheduledItem,
        _ day: CalendarDay,
        _ outcome: ScheduledOutcome,
        automatically: Bool? = nil,
    ) -> ScheduledItem {
        var item = item
        item.occurrences.append(
            ScheduledOccurrence(
                id: ScheduledKey.occurrenceID(item: item.id, day: day),
                day: day,
                outcome: outcome,
                recordedAutomatically: automatically,
                createdAt: Fix.created,
            )
        )
        return item
    }

    @Test("S9: each upcoming occurrence is reminded on its due day at 09:00 local time")
    func dueDayAtNine() {
        let item = electricity()
        let reminders = plan([item], limit: 3)
        #expect(reminders.map(\.day) == [Fix.day(2026, 11, 15), Fix.day(2026, 12, 15), Fix.day(2027, 1, 15)])
        #expect(reminders.first?.fireDate == Fix.date(2026, 11, 15, 9))
        #expect(reminders.allSatisfy { $0.time == .standard && $0.item.id == item.id })
    }

    @Test("Identifiers come from the occurrence IDs, so planning twice gives the same requests")
    func deterministicIdentifiers() {
        let item = electricity()
        let first = plan([item], limit: 2)
        let again = plan([item], now: Fix.date(2026, 10, 20, 8, zone: "UTC"), limit: 2)
        let occurrence = ScheduledKey.occurrenceID(item: item.id, day: Fix.day(2026, 11, 15))
        #expect(first.first?.id == "scheduled.reminder.\(occurrence.uuidString)")
        #expect(first.map(\.id) == again.map(\.id))
        #expect(Set(first.map(\.id)).count == 2)
    }

    @Test("Today's occurrence is reminded while 09:00 is still ahead, and not after it")
    func todayOnlyWhileAhead() {
        let item = electricity(day: 20)
        #expect(plan([item], now: Fix.date(2026, 10, 20, 8)).first?.day == Fix.day(2026, 10, 20))
        #expect(plan([item], now: Fix.date(2026, 10, 20, 10)).first?.day == Fix.day(2026, 11, 20))
    }

    @Test("D340.7: an overdue occurrence never notifies again, and catch-up's missed days send none")
    func overdueNeverNotifies() {
        let reminders = plan([electricity(day: 15)], now: Fix.date(2026, 10, 20, 8))
        #expect(reminders.allSatisfy { $0.day >= Fix.day(2026, 10, 20) })
        #expect(!reminders.contains { $0.day == Fix.day(2026, 10, 15) })
    }

    @Test("Paying or skipping a manual occurrence drops its reminder")
    func settledManualDropped() {
        let today = Fix.day(2026, 10, 20)
        let paid = settled(electricity(day: 20), today, .posted)
        let skipped = settled(electricity(day: 20), today, .skipped)
        #expect(plan([paid]).first?.day == Fix.day(2026, 11, 20))
        #expect(plan([skipped]).first?.day == Fix.day(2026, 11, 20))
    }

    @Test(
        "S11, S81: an automatic occurrence recorded at catch-up earlier today keeps its one reminder; a skip drops it"
    )
    func automaticRecordedKeepsOne() {
        let today = Fix.day(2026, 10, 20)
        let recorded = settled(electricity(day: 20, automatic: true), today, .posted, automatically: true)
        let reminders = plan([recorded], limit: 2)
        #expect(reminders.map(\.day) == [today, Fix.day(2026, 11, 20)])
        #expect(reminders.first?.kind == .automatic)
        #expect(reminders.first?.fireDate == Fix.date(2026, 10, 20, 9))
        let skipped = settled(electricity(day: 20, automatic: true), today, .skipped)
        #expect(plan([skipped]).first?.day == Fix.day(2026, 11, 20))
    }

    @Test("D354.1: an automatic occurrence the user paid gets no reminder; only the app's recording keeps it")
    func automaticPaidByUserDropped() {
        let today = Fix.day(2026, 10, 20)
        let paid = settled(electricity(day: 20, automatic: true), today, .posted)
        #expect(plan([paid]).first?.day == Fix.day(2026, 11, 20))
        let unmarked = settled(electricity(day: 20, automatic: true), today, .posted, automatically: false)
        #expect(plan([unmarked]).first?.day == Fix.day(2026, 11, 20))
        let recorded = settled(electricity(day: 20, automatic: true), today, .posted, automatically: true)
        #expect(plan([recorded]).first?.day == today)
    }

    @Test("Manual and automatic items are told apart")
    func kinds() {
        let manual = electricity(day: 21)
        var rent = electricity(day: 22, automatic: true)
        rent.details = "Rent"
        let reminders = plan([manual, rent], limit: 2)
        #expect(reminders.map(\.kind) == [.manual, .automatic])
    }

    @Test("Items without Notify when due, and deleted items, get no reminders")
    func onlyNotifiedLiveItems() {
        var deleted = electricity()
        deleted.deletedAt = Fix.created
        #expect(plan([electricity(notifies: false), deleted]).isEmpty)
    }

    @Test("D337.1: no reminder before the creation day; the end date is the last one")
    func creationAndEnd() {
        var item = electricity(day: 25, end: Fix.day(2026, 12, 25))
        item.createdAt = Fix.date(2026, 11, 26)
        #expect(plan([item]).map(\.day) == [Fix.day(2026, 12, 25)])
    }

    /// D427.1: the pending 20 Oct is October's occurrence, so the next reminder after it is 25 Nov.
    @Test("A pending day kept from before an edit is reminded when it's today")
    func pendingToday() {
        var item = electricity(day: 25)
        item.occurrences.append(
            ScheduledOccurrence(
                id: ScheduledKey.occurrenceID(item: item.id, day: Fix.day(2026, 10, 20)),
                day: Fix.day(2026, 10, 20),
                outcome: .pending,
                createdAt: Fix.created,
            )
        )
        #expect(plan([item], limit: 2).map(\.day) == [Fix.day(2026, 10, 20), Fix.day(2026, 11, 25)])
    }

    @Test("S10: a changed Reminder Time moves every reminder to it")
    func reminderTime() {
        let reminders = plan([electricity()], time: ReminderTime(hour: 18, minute: 30), limit: 2)
        #expect(reminders.first?.fireDate == Fix.date(2026, 11, 15, 18).addingTimeInterval(30 * 60))
        #expect(reminders.allSatisfy { $0.time == ReminderTime(hour: 18, minute: 30) })
    }

    @Test("S23: in Europe/London the reminder is 09:00 London time on the due day")
    func timeZoneChange() {
        let london = TimeZone(identifier: "Europe/London")!
        let reminders = plan([electricity()], now: Fix.date(2026, 10, 20, 8, zone: "Europe/London"), zone: london)
        #expect(reminders.first?.fireDate == Fix.date(2026, 11, 15, 9, zone: "Europe/London"))
    }

    @Test("S25: with 64+ notified items, only the nearest 60 reminders are planned, in time order")
    func cappedAtTheBudget() {
        let items = (0..<70)
            .map { index in
                var item = electricity(day: 1 + index % 28)
                item.id = UUID(uuidString: String(format: "5D000000-0000-4000-8000-%012d", index))!
                return item
            }
        let reminders = plan(items)
        #expect(ScheduledReminderPlanner.systemPendingLimit == 64)
        #expect(ScheduledReminderPlanner.pendingBudget == 60)
        #expect(reminders.count == ScheduledReminderPlanner.pendingBudget)
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
        let latest = reminders.last!.fireDate
        let all = plan(items, limit: 10_000)
        #expect(all.count > 64)
        #expect(all.dropFirst(reminders.count).allSatisfy { $0.fireDate >= latest })
    }

    @Test("A daily item alone fills the budget with its next 60 days")
    func dailyFillsTheCap() {
        let reminders = plan([electricity(day: 1, rule: .daily)])
        #expect(reminders.count == 60)
        #expect(reminders.first?.day == Fix.day(2026, 10, 20))
        #expect(reminders.last?.day == ScheduleCalendar.adding(days: 59, to: Fix.day(2026, 10, 20)))
    }

    @Test("One budget for every item: a near weekly item and a far monthly one share it, earliest dates first")
    func sharedBudgetEarliestWin() {
        // Weekly on Thursdays (from 20 Aug), next on 22 Oct; monthly on the 15th, next on 15 Nov. 60 weekly dates
        // alone would reach Dec 2027, so the monthly item gets only the slots dated before the 60th overall.
        var weekly = electricity(day: 20, rule: .weekly)
        weekly.id = UUID(uuidString: "5D000000-0000-4000-8000-00000000000A")!
        var monthly = electricity(day: 15, rule: .monthly)
        monthly.id = UUID(uuidString: "5D000000-0000-4000-8000-00000000000B")!
        let reminders = plan([monthly, weekly])
        #expect(reminders.count == ScheduledReminderPlanner.pendingBudget)
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
        #expect(reminders.first?.item.id == weekly.id)
        #expect(reminders.first?.day == Fix.day(2026, 10, 22))
        let monthlyDays = reminders.filter { $0.item.id == monthly.id }.map(\.day)
        let weeklyDays = reminders.filter { $0.item.id == weekly.id }.map(\.day)
        // Both items are in it; neither has a cap of its own.
        #expect(!monthlyDays.isEmpty)
        #expect(weeklyDays.count > monthlyDays.count)
        #expect(weeklyDays.count + monthlyDays.count == 60)
        // Whatever was left out is never earlier than the last date kept, for either item.
        let latest = reminders.last!.fireDate
        let everything = plan([monthly, weekly], limit: 10_000)
        #expect(everything.filter { !reminders.contains($0) }.allSatisfy { $0.fireDate >= latest })
        // The kept monthly dates are exactly its occurrences up to that last date.
        let monthlyAll = everything.filter { $0.item.id == monthly.id && $0.fireDate <= latest }.map(\.day)
        #expect(monthlyDays == monthlyAll)
        #expect(monthlyDays.first == Fix.day(2026, 11, 15))
    }

    @Test("A budget smaller than one item's dates still goes to the nearest dates across items")
    func sharedBudgetSmall() {
        let weekly = electricity(day: 20, rule: .weekly)
        let monthly = electricity(day: 15, rule: .monthly)
        let reminders = plan([monthly, weekly], limit: 5)
        // 22 Oct, 29 Oct, 5 Nov and 12 Nov weekly; then 15 Nov monthly, before 19 Nov weekly.
        #expect(
            reminders.map(\.day) == [
                Fix.day(2026, 10, 22), Fix.day(2026, 10, 29), Fix.day(2026, 11, 5), Fix.day(2026, 11, 12),
                Fix.day(2026, 11, 15),
            ]
        )
        #expect(reminders.last?.item.id == monthly.id)
    }

    @Test("A stored reminder time out of range is clamped")
    func clamped() {
        #expect(ReminderTime(hour: 30, minute: -5) == ReminderTime(hour: 23, minute: 0))
        #expect(ReminderTime(minutesAfterMidnight: 18 * 60 + 30) == ReminderTime(hour: 18, minute: 30))
        #expect(ReminderTime(minutesAfterMidnight: 99_999).minutesAfterMidnight == 24 * 60 - 1)
    }
}

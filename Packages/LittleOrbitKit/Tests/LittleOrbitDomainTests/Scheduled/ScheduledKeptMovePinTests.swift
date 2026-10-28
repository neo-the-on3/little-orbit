import Foundation
import LittleOrbitDomain
import Testing

/// Pins for what keeps or removes an occurrence's own values after a Starts or End date edit (D435, D442, Tech
/// Architect's review of #326): settled records never change, and what's on the new rule is judged with the edit's
/// `resumesOn`. Made-up data in `Asia/Kolkata`: Phone Plan, ₹199.00 weekly on Mondays from Mon 12 Oct 2026, from
/// Everyday Savings (INR), with 12 and 19 Oct paid. Occurrences are edited on Tue 20 Oct; the item on Wed 21 Oct.
@MainActor
@Suite("Kept and removed occurrence edits: settled records and resumesOn (D435, D442)")
struct ScheduledKeptMovePinTests {
    private typealias Fix = ScheduledFixture
    private static let kolkata = TimeZone(identifier: Fix.zone)!

    private static func phonePlan() throws -> (FakeScheduleRepository, UUID) {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        var phone = Fix.rent(amount: 199, start: Fix.day(2026, 10, 12), rule: .weekly, automatic: false)
        phone.details = "Phone Plan"
        phone.notifiesWhenDue = true
        let id = try repository.useCases().save(phone, payee: nil).after.id
        for day in [Fix.day(2026, 10, 12), Fix.day(2026, 10, 19)] {
            _ = try repository.settleScheduledOccurrence(.pay(itemID: id, occurrence: day, postedOn: day))
        }
        repository.now = Fix.date(2026, 10, 20)
        return (repository, id)
    }

    /// "This occurrence only" on 20 Oct: `key` moved to `due`, with `amount` of its own when given.
    private static func edit(
        _ repository: FakeScheduleRepository,
        _ key: CalendarDay,
        to due: CalendarDay? = nil,
        amount: Decimal? = nil,
    ) throws {
        var item = repository.snapshot.scheduledItems[0]
        if let amount {
            item.amount = amount
        }
        let save = ScheduledOccurrenceSave(occurrence: key, dueDay: due ?? key, scope: .thisOccurrence)
        _ = try repository.useCases().update(item, editing: save, payee: nil)
    }

    private static func pay(_ repository: FakeScheduleRepository, _ id: UUID, _ key: CalendarDay) throws {
        let pay = ScheduledSettlement.pay(itemID: id, occurrence: key, postedOn: Fix.day(2026, 10, 20))
        _ = try repository.settleScheduledOccurrence(pay)
    }

    private static func skip(_ repository: FakeScheduleRepository, _ id: UUID, _ key: CalendarDay) throws {
        _ = try repository.settleScheduledOccurrence(.skip(itemID: id, occurrence: key))
    }

    /// The whole-item save on 21 Oct.
    private static func save(
        _ repository: FakeScheduleRepository,
        _ change: (inout ScheduledItem) -> Void,
    ) throws -> ScheduledItemSaveChange {
        repository.now = Fix.date(2026, 10, 21)
        var item = repository.snapshot.scheduledItems[0]
        change(&item)
        return try repository.useCases().update(item, payee: nil)
    }

    private static func due(_ item: ScheduledItem) -> [CalendarDay] {
        ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 30)).map(\.day)
    }

    // MARK: Settled records never change

    @Test("D435: a Starts edit never turns a paid or skipped move pending; only the open move becomes pending")
    func startsEditLeavesSettledMovesAlone() throws {
        // 26 Oct moved to Fri 30 Oct and paid early; 2 Nov moved to Fri 6 Nov and skipped; 9 Nov moved to Fri 13
        // Nov and left open. Then Starts becomes Tue 27 Oct, so all three keys are off the rule.
        let (repository, id) = try Self.phonePlan()
        try Self.edit(repository, Fix.day(2026, 10, 26), to: Fix.day(2026, 10, 30))
        try Self.pay(repository, id, Fix.day(2026, 10, 26))
        try Self.edit(repository, Fix.day(2026, 11, 2), to: Fix.day(2026, 11, 6))
        try Self.skip(repository, id, Fix.day(2026, 11, 2))
        try Self.edit(repository, Fix.day(2026, 11, 9), to: Fix.day(2026, 11, 13))
        let settled = repository.snapshot.scheduledItems[0].occurrences.filter(\.outcome.isSettled)
        let transactions = repository.snapshot.transactions
        let change = try Self.save(repository) { $0.startDay = Fix.day(2026, 10, 27) }
        let item = repository.snapshot.scheduledItems[0]
        #expect(change.removed.isEmpty)
        #expect(item.occurrences.filter(\.outcome.isSettled) == settled)
        #expect(item.occurrence(on: Fix.day(2026, 10, 26))?.outcome == .posted)
        #expect(item.occurrence(on: Fix.day(2026, 11, 2))?.outcome == .skipped)
        #expect(repository.snapshot.transactions == transactions)
        #expect(item.occurrence(on: Fix.day(2026, 11, 9))?.outcome == .pending)
        let due = Self.due(item)
        #expect(due.contains(Fix.day(2026, 11, 13)))
        #expect(!due.contains(Fix.day(2026, 10, 30)) && !due.contains(Fix.day(2026, 11, 6)))
    }

    @Test("D442.1: an End date edit never turns pending or removes a paid or skipped move, before or after the End")
    func endDateEditLeavesSettledMovesAlone() throws {
        // 9 Nov moved to Wed 4 Nov and paid early; 2 Nov moved to Tue 10 Nov and skipped. End becomes Sat 7 Nov: 9
        // Nov's key is past it, and 2 Nov's moved day is too.
        let (repository, id) = try Self.phonePlan()
        try Self.edit(repository, Fix.day(2026, 11, 9), to: Fix.day(2026, 11, 4))
        try Self.pay(repository, id, Fix.day(2026, 11, 9))
        try Self.edit(repository, Fix.day(2026, 11, 2), to: Fix.day(2026, 11, 10))
        try Self.skip(repository, id, Fix.day(2026, 11, 2))
        let settled = repository.snapshot.scheduledItems[0].occurrences.filter(\.outcome.isSettled)
        let transactions = repository.snapshot.transactions
        let change = try Self.save(repository) { $0.endDay = Fix.day(2026, 11, 7) }
        let item = repository.snapshot.scheduledItems[0]
        #expect(change.removed.isEmpty)
        #expect(item.occurrences.filter(\.outcome.isSettled) == settled)
        #expect(item.occurrence(on: Fix.day(2026, 11, 9))?.outcome == .posted)
        #expect(item.occurrence(on: Fix.day(2026, 11, 2))?.outcome == .skipped)
        #expect(repository.snapshot.transactions == transactions)
        #expect(Self.due(item) == [Fix.day(2026, 10, 26)])
    }

    // MARK: Judged with the edit's resumesOn

    /// 2 Nov is paid early, so a Starts edit resumes on Tue 3 Nov. Starts becomes Mon 5 Oct: still Mondays, but 26
    /// Oct is before the new rule resumes, so it's off the rule.
    private static func resumingAfterPaidEarly(
        _ edit: (FakeScheduleRepository) throws -> Void
    ) throws -> (FakeScheduleRepository, ScheduledItemSaveChange) {
        let (repository, id) = try Self.phonePlan()
        try Self.pay(repository, id, Fix.day(2026, 11, 2))
        try edit(repository)
        let change = try Self.save(repository) { $0.startDay = Fix.day(2026, 10, 5) }
        #expect(repository.snapshot.scheduledItems[0].resumesOn == Fix.day(2026, 11, 3))
        return (repository, change)
    }

    @Test("D435: a move to Fri 30 Oct whose key is before the edit's resumesOn (3 Nov) stays pending, due and reminded")
    func moveBeforeResumesOnStaysDue() throws {
        let (repository, change) = try Self.resumingAfterPaidEarly { repository in
            try Self.edit(repository, Fix.day(2026, 10, 26), to: Fix.day(2026, 10, 30))
        }
        let item = repository.snapshot.scheduledItems[0]
        #expect(change.removed.isEmpty)
        #expect(item.occurrence(on: Fix.day(2026, 10, 26))?.outcome == .pending)
        #expect(Self.due(item).first == Fix.day(2026, 10, 30))
        let board = ScheduledBoard.make(repository.snapshot, today: Fix.day(2026, 10, 30))
        #expect(board.dueToday.contains { $0.key == Fix.day(2026, 10, 26) })
        let reminders = ScheduledReminderPlanner.plan(
            [item],
            now: Fix.date(2026, 10, 21),
            timeZone: Self.kolkata,
            time: .standard,
            limit: 3,
        )
        #expect(reminders.first?.id == ScheduledReminder.identifier(item: item.id, day: Fix.day(2026, 10, 26)))
        #expect(reminders.first?.fireDate == Fix.date(2026, 10, 30, 9))
    }

    @Test("D442.2: an amount-only edit whose key is before the edit's resumesOn (3 Nov) is removed and reported")
    func amountEditBeforeResumesOnIsRemoved() throws {
        let (repository, change) = try Self.resumingAfterPaidEarly { repository in
            try Self.edit(repository, Fix.day(2026, 10, 26), amount: 249)
        }
        let key = Fix.day(2026, 10, 26)
        #expect(change.removed == [.init(reason: .editedOffSchedule, key: key, dueDay: key)])
        #expect(repository.snapshot.scheduledItems[0].occurrence(on: key) == nil)
    }
}

import Foundation
import LittleOrbitDomain
import Testing

/// Pins for Tech Architect's mutants M6 and M7 (review 5691356633): the End date is the last day the schedule
/// has, so an occurrence due exactly on it is kept. Made-up data in `Asia/Kolkata`: Phone Plan, ₹199.00 weekly on
/// Mondays from Mon 12 Oct 2026, from Everyday Savings (INR), with 12 and 19 Oct paid. On Tue 20 Oct one Monday is
/// edited for this occurrence only; on Wed 21 Oct the End date is set. Every save goes through the use cases.
@MainActor
@Suite("An occurrence due exactly on the new End date is kept (M6, M7)")
struct ScheduledEndBoundaryPinTests {
    private typealias Fix = ScheduledFixture

    /// `edit` applied to `key` on 20 Oct for this occurrence only, then End set to `end` on 21 Oct.
    private static func example(
        key: CalendarDay,
        movedTo: CalendarDay? = nil,
        amount: Decimal? = nil,
        end: CalendarDay,
    ) throws -> (repository: FakeScheduleRepository, change: ScheduledItemSaveChange) {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let useCases = repository.useCases()
        var phone = Fix.rent(amount: 199, start: Fix.day(2026, 10, 12), rule: .weekly, automatic: false)
        phone.details = "Phone Plan"
        let saved = try useCases.save(phone, payee: nil).after
        for day in [Fix.day(2026, 10, 12), Fix.day(2026, 10, 19)] {
            _ = try repository.settleScheduledOccurrence(.pay(itemID: saved.id, occurrence: day, postedOn: day))
        }
        repository.now = Fix.date(2026, 10, 20)
        var edited = repository.snapshot.scheduledItems[0]
        if let amount {
            edited.amount = amount
        }
        let save = ScheduledOccurrenceSave(occurrence: key, dueDay: movedTo ?? key, scope: .thisOccurrence)
        _ = try useCases.update(edited, editing: save, payee: nil)
        repository.now = Fix.date(2026, 10, 21)
        var ended = repository.snapshot.scheduledItems[0]
        ended.endDay = end
        return (repository, try useCases.update(ended, payee: nil))
    }

    @Test("M6: Mon 2 Nov moved to Sat 31 Oct is kept, pending and due on 31 Oct, when End becomes 31 Oct")
    func moveDueOnTheNewEndIsKept() throws {
        let key = Fix.day(2026, 11, 2)
        let end = Fix.day(2026, 10, 31)
        let (repository, change) = try Self.example(key: key, movedTo: end, end: end)
        #expect(change.removed.isEmpty)
        let item = repository.snapshot.scheduledItems[0]
        #expect(item.endDay == end)
        #expect(item.occurrence(on: key)?.outcome == .pending)
        #expect(item.dueDay(of: key) == end)
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 30))
        #expect(due.map(\.day) == [Fix.day(2026, 10, 26), end])
        #expect(due.last?.key == key)
    }

    @Test("M7: ₹249.00 on Mon 26 Oct is kept, still ₹249.00 and due on 26 Oct, when End becomes 26 Oct")
    func amountEditOnTheNewEndIsKept() throws {
        let key = Fix.day(2026, 10, 26)
        let (repository, change) = try Self.example(key: key, amount: 249, end: key)
        #expect(change.removed.isEmpty)
        let item = repository.snapshot.scheduledItems[0]
        #expect(item.endDay == key)
        #expect(item.occurrence(on: key)?.outcome == .edited)
        #expect(item.resolved(for: key).amount == 249)
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 30))
        #expect(due.map(\.day) == [key])
    }
}

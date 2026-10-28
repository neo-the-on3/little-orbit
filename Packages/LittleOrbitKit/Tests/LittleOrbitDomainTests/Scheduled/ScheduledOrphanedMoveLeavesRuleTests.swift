import Foundation
import LittleOrbitDomain
import Testing

/// D435.3: a "This occurrence only" move whose own day a Starts edit takes off the rule stays due on its moved day.
/// Made-up data in `Asia/Kolkata`: Gym, ₹500 weekly from Mon 12 Oct 2026, with 12 and 19 Oct paid. On Tue 20 Oct,
/// Mon 26 Oct is moved to Wed 4 Nov for this occurrence only, then Starts becomes Tue 27 Oct, so 26 Oct is off the
/// rule. Before D435 the 4 Nov record was still stored but was in no list: not due, not on the board.
@Suite("A this-only move whose own day leaves the rule (D435.3)")
struct ScheduledOrphanedMoveLeavesRuleTests {
    private typealias Fix = ScheduledFixture
    private static let today = Fix.day(2026, 10, 20)
    private static let key = Fix.day(2026, 10, 26)
    private static let movedTo = Fix.day(2026, 11, 4)

    /// The sequence, through the real save paths: create, pay 12 and 19 Oct, move 26 Oct, then edit Starts.
    private func example() throws -> LedgerSnapshot {
        let gym = Fix.rent(amount: 500, start: Fix.day(2026, 10, 12), rule: .weekly, automatic: false)
        var snapshot = try LedgerBook.savingScheduledItem(gym, in: Fix.ledger, today: Self.today, now: Fix.created)
        for day in [Fix.day(2026, 10, 12), Fix.day(2026, 10, 19)] {
            snapshot =
                try LedgerBook.settlingScheduledOccurrence(
                    .pay(itemID: gym.id, occurrence: day, postedOn: day),
                    in: snapshot,
                    now: Fix.date(2026, 10, 20),
                )
                .snapshot
        }
        let save = ScheduledOccurrenceSave(occurrence: Self.key, dueDay: Self.movedTo, scope: .thisOccurrence)
        snapshot = try LedgerBook.savingScheduledOccurrence(
            snapshot.scheduledItems[0],
            editing: save,
            in: snapshot,
            today: Self.today,
            now: Fix.date(2026, 10, 20),
        )
        var tuesdays = snapshot.scheduledItems[0]
        tuesdays.startDay = Fix.day(2026, 10, 27)
        return try LedgerBook.savingScheduledItem(
            tuesdays,
            in: snapshot,
            today: Self.today,
            now: Fix.date(2026, 10, 20, 11),
        )
    }

    /// What D435 keeps for the moved record. Whether Tue 3 Nov, in the period 4 Nov takes, is still created is
    /// #316's taken-period check (D437), so it isn't pinned here.
    @Test("D435.3: after Starts moves to Tue 27 Oct, 26 Oct's move to Wed 4 Nov is pending, due and on the board")
    func movedDayLeavesTheRule() throws {
        let snapshot = try example()
        let item = snapshot.scheduledItems[0]
        #expect(item.startDay == Fix.day(2026, 10, 27))
        #expect(item.occurrence(on: Self.key)?.outcome == .pending)
        #expect(item.dueDay(of: Self.key) == Self.movedTo)
        // Due on 4 Nov under 26 Oct's key, and the next one after it is Tue 10 Nov.
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 30))
        #expect(due.contains { $0.key == Self.key && $0.day == Self.movedTo })
        let later = due.filter { $0.day > Self.movedTo }.map(\.day)
        #expect(later.first == Fix.day(2026, 11, 10))
        #expect(ScheduleCalendar.nextOccurrence(of: item, after: Self.movedTo)?.day == Fix.day(2026, 11, 10))
        // The board: due today on 4 Nov.
        let board = ScheduledBoard.make(snapshot, today: Self.movedTo)
        #expect(board.dueToday.contains { $0.key == Self.key && $0.day == Self.movedTo })
        // Pay accepts it and records it on 4 Nov for ₹500.
        let paid = try LedgerBook.settlingScheduledOccurrence(
            .pay(itemID: item.id, occurrence: Self.key, postedOn: Self.movedTo),
            in: snapshot,
            now: Fix.date(2026, 11, 4),
        )
        #expect(paid.transaction?.amount == 500)
        #expect(paid.snapshot.scheduledItems[0].occurrence(on: Self.key)?.outcome == .posted)
    }
}

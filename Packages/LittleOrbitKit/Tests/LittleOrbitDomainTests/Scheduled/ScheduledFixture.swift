import Foundation
import LittleOrbitDomain

/// Made-up accounts and categories for the scheduled-item tests (#26), dated in `Asia/Kolkata`.
enum ScheduledFixture {
    static let zone = "Asia/Kolkata"
    static let savingsID = UUID(uuidString: "5C000000-0000-4000-8000-000000000001")!
    static let fundID = UUID(uuidString: "5C000000-0000-4000-8000-000000000002")!
    static let housingID = UUID(uuidString: "5C000000-0000-4000-8000-000000000003")!
    static let salaryID = UUID(uuidString: "5C000000-0000-4000-8000-000000000004")!
    static let bakeryID = UUID(uuidString: "5C000000-0000-4000-8000-000000000005")!

    static let created = date(2026, 7, 1)

    static var ledger: LedgerSnapshot {
        LedgerSnapshot(
            accounts: [
                Account(
                    id: savingsID,
                    name: "Everyday Savings",
                    type: .savings,
                    currencyCode: "INR",
                    openingBalance: 100_000,
                    createdAt: created,
                ),
                Account(id: fundID, name: "Long Term Fund", type: .savings, currencyCode: "INR", createdAt: created),
            ],
            categories: [
                TransactionCategory(id: housingID, name: "Housing", kind: .expense, createdAt: created),
                TransactionCategory(id: salaryID, name: "Salary", kind: .income, createdAt: created),
            ],
            payees: [Payee(id: bakeryID, name: "Corner Bakery", createdAt: created)],
        )
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, zone: String = zone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func rent(
        id: UUID = UUID(),
        amount: Decimal = 25_000,
        start: CalendarDay = day(2026, 8, 1),
        rule: ScheduleRepeat = .monthly,
        end: CalendarDay? = nil,
        automatic: Bool = true,
    ) -> ScheduledItem {
        ScheduledItem(
            id: id,
            type: .expense,
            amount: amount,
            accountID: savingsID,
            categoryID: housingID,
            details: "Rent",
            startDay: start,
            repeatRule: rule,
            endDay: end,
            processesAutomatically: automatic,
            timeZoneID: zone,
            createdAt: created,
        )
    }

    static func transfer(start: CalendarDay, end: CalendarDay?) -> ScheduledItem {
        ScheduledItem(
            type: .transfer,
            amount: 10_000,
            accountID: savingsID,
            transferAccountID: fundID,
            details: "To Long Term Fund",
            startDay: start,
            repeatRule: .monthly,
            endDay: end,
            timeZoneID: zone,
            createdAt: created,
        )
    }
}

/// A fake `ScheduleRepository`: one snapshot, changed through `LedgerBook` like the real stores, with a settable
/// clock so a test can move days, relaunch or turn the clock back.
@MainActor
final class FakeScheduleRepository: ScheduleRepository {
    var snapshot: LedgerSnapshot
    var now = ScheduledFixture.date(2026, 10, 20)
    var saves = 0

    init(_ snapshot: LedgerSnapshot = ScheduledFixture.ledger) {
        self.snapshot = snapshot
    }

    func scheduleLedger() throws -> LedgerSnapshot {
        snapshot
    }

    func saveScheduledItem(_ item: ScheduledItem, today: CalendarDay, now: Date) throws {
        snapshot = try LedgerBook.savingScheduledItem(item, in: snapshot, today: today, now: now)
        saves += 1
    }

    func saveScheduledItem(
        _ item: ScheduledItem,
        payee: ScheduledPendingPayee?,
        today: CalendarDay,
        now: Date,
    ) throws -> ScheduledItemSaveChange {
        let outcome = try LedgerBook.savingScheduledItem(item, payee: payee, in: snapshot, today: today, now: now)
        snapshot = outcome.snapshot
        saves += 1
        return outcome.change
    }

    func updateScheduledItem(
        _ item: ScheduledItem,
        payee: ScheduledPendingPayee?,
        today: CalendarDay,
        now: Date,
    ) throws -> ScheduledItemSaveChange {
        let outcome = try LedgerBook.updatingScheduledItem(item, payee: payee, in: snapshot, today: today, now: now)
        snapshot = outcome.snapshot
        saves += 1
        return outcome.change
    }

    func revertScheduledItemSave(_ change: ScheduledItemSaveChange, undone: Bool) throws -> ScheduledItemSaveRevert {
        let outcome = try LedgerBook.revertingScheduledItemSave(change, undone: undone, in: snapshot, now: now)
        snapshot = outcome.snapshot
        saves += 1
        return outcome.result
    }

    func updateScheduledOccurrence(
        _ item: ScheduledItem,
        editing save: ScheduledOccurrenceSave,
        payee: ScheduledPendingPayee?,
        today: CalendarDay,
        now: Date,
    ) throws -> ScheduledItemSaveChange {
        let outcome = try LedgerBook.updatingScheduledOccurrence(
            item,
            editing: save,
            payee: payee,
            in: snapshot,
            today: today,
            now: now,
        )
        snapshot = outcome.snapshot
        saves += 1
        return outcome.change
    }

    func deleteScheduledItem(id: UUID) throws {
        snapshot = try LedgerBook.deletingScheduledItem(id: id, in: snapshot)
        saves += 1
    }

    func settleScheduledOccurrence(_ settlement: ScheduledSettlement) throws -> ScheduledSettlementChange? {
        let outcome = try LedgerBook.settlingScheduledOccurrence(settlement, in: snapshot, now: now)
        snapshot = outcome.snapshot
        saves += 1
        return outcome.change
    }

    func unsettleScheduledOccurrence(_ change: ScheduledSettlementChange) throws -> ScheduledSettlementRevert {
        let outcome = try LedgerBook.unsettlingScheduledOccurrence(change, in: snapshot, now: now)
        snapshot = outcome.snapshot
        saves += 1
        return outcome.result
    }

    func resettleScheduledOccurrence(_ change: ScheduledSettlementChange) throws -> ScheduledSettlementRevert {
        let outcome = try LedgerBook.resettlingScheduledOccurrence(change, in: snapshot, now: now)
        snapshot = outcome.snapshot
        saves += 1
        return outcome.result
    }

    func catchUpScheduledItems(today: CalendarDay, pruningOrphans: Bool, holding: Set<UUID>) throws
        -> ScheduledCatchUp
    {
        let outcome = LedgerBook.catchingUpScheduledItems(
            in: snapshot,
            today: today,
            now: now,
            pruningOrphans: pruningOrphans,
            holding: holding,
        )
        snapshot = outcome.snapshot
        saves += 1
        return outcome.result
    }

    /// The use cases one window or one launch builds, reading this fake's clock in `zone`.
    func useCases(zone: String = ScheduledFixture.zone) -> DefaultScheduledUseCases {
        DefaultScheduledUseCases(
            repository: self,
            now: { [unowned self] in self.now },
            timeZone: { TimeZone(identifier: zone)! },
        )
    }

    func posted(for itemID: UUID) -> [Transaction] {
        snapshot.transactions.filter { $0.scheduledTemplateID == itemID }.sorted { $0.date < $1.date }
    }
}

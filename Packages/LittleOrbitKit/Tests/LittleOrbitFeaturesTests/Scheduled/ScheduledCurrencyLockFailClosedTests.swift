import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tech Architect's n1 on #207: when the scheduled items can't be read, Edit Account's currency lock (D381.3) fails
/// closed, with the existing lock message. Made-up data.
@MainActor
@Suite("Edit Account's currency lock fails closed (D381.3, n1)")
struct ScheduledCurrencyLockFailClosedTests {
    @Test("A failed read of the scheduled items locks the currency, with the usual message")
    func unreadableItemsLock() throws {
        let scene = try ScheduledScene()
        let travel = Account(name: "Travel Wallet", type: .cash, currencyCode: "USD", sortOrder: 2)
        try scene.repository.saveAccount(travel)
        let unreadable = DefaultScheduledUseCases(
            repository: UnreadableScheduleStore(),
            now: { scene.now },
            timeZone: { TimeZone(identifier: ScheduledScene.zone)! },
        )
        let scheduled = ScheduledFeature(
            useCases: ScheduledScreenUseCases(
                load: unreadable,
                manage: unreadable,
                catchUp: unreadable,
                notices: ScheduledCatchUpNotices(store: InMemoryScheduledCatchUpNoticeStore()),
            ),
            updates: scene.updates,
            locale: Locale(identifier: "en_IN"),
        )
        let accounts = AccountsFeature(
            useCases: AccountUseCases(repository: scene.repository),
            plannedItems: scheduled,
            defaultCurrency: "INR",
            locale: Locale(identifier: "en_IN"),
        )
        let form = accounts.makeForm(.edit(travel.id))
        #expect(form.isCurrencyLocked)
        #expect(
            form.currencyLockMessage
                == "Currency can’t be changed once the account has transactions or scheduled items."
        )
        // A new account has no currency to protect.
        #expect(!accounts.makeForm(.new).isCurrencyLocked)
    }
}

extension ScheduledCurrencyLockFailClosedTests {
    @Test("n5: a failed read of the scheduled items throws, and the account delete confirmation isn't shown")
    func unreadableItemsNoDeletePrompt() throws {
        let scene = try ScheduledScene()
        let travel = Account(name: "Travel Wallet", type: .cash, currencyCode: "USD", sortOrder: 2)
        try scene.repository.saveAccount(travel)
        let unreadable = DefaultScheduledUseCases(
            repository: UnreadableScheduleStore(),
            now: { scene.now },
            timeZone: { TimeZone(identifier: ScheduledScene.zone)! },
        )
        let scheduled = ScheduledFeature(
            useCases: ScheduledScreenUseCases(
                load: unreadable,
                manage: unreadable,
                catchUp: unreadable,
                notices: ScheduledCatchUpNotices(store: InMemoryScheduledCatchUpNoticeStore()),
            ),
            updates: scene.updates,
            locale: Locale(identifier: "en_IN"),
        )
        #expect(throws: (any Error).self) { try scheduled.scheduledItems() }
        let accounts = AccountsFeature(
            useCases: AccountUseCases(repository: scene.repository),
            plannedItems: scheduled,
            defaultCurrency: "INR",
            locale: Locale(identifier: "en_IN"),
        )
        accounts.accounts.load()
        #expect(accounts.accounts.account(id: travel.id) != nil)
        #expect(accounts.accounts.deletePrompt(accountID: travel.id) == nil, "Fails closed: no count without items")
        #expect(accounts.accounts.errorMessage != nil)
    }
}

/// A schedule store whose read fails; nothing else is called here.
@MainActor
private final class UnreadableScheduleStore: ScheduleRepository {
    struct Failure: Error {}

    func scheduleLedger() throws -> LedgerSnapshot { throw Failure() }
    func saveScheduledItem(_: ScheduledItem, today _: CalendarDay, now _: Date) throws { throw Failure() }
    func saveScheduledItem(_: ScheduledItem, payee _: ScheduledPendingPayee?, today _: CalendarDay, now _: Date)
        throws -> ScheduledItemSaveChange
    { throw Failure() }
    func updateScheduledItem(_: ScheduledItem, payee _: ScheduledPendingPayee?, today _: CalendarDay, now _: Date)
        throws -> ScheduledItemSaveChange
    { throw Failure() }
    func revertScheduledItemSave(_: ScheduledItemSaveChange, undone _: Bool) throws -> ScheduledItemSaveRevert {
        throw Failure()
    }
    func deleteScheduledItem(id _: UUID) throws { throw Failure() }
    func settleScheduledOccurrence(_: ScheduledSettlement) throws -> ScheduledSettlementChange? { throw Failure() }
    func unsettleScheduledOccurrence(_: ScheduledSettlementChange) throws -> ScheduledSettlementRevert {
        throw Failure()
    }
    func resettleScheduledOccurrence(_: ScheduledSettlementChange) throws -> ScheduledSettlementRevert {
        throw Failure()
    }
    func catchUpScheduledItems(today _: CalendarDay, pruningOrphans _: Bool) throws -> ScheduledCatchUp {
        throw Failure()
    }
}

import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Made-up data in `Asia/Kolkata`, over the in-memory store (#26).
@MainActor
final class ScheduledScene {
    let repository = InMemoryLedgerRepository(seedPending: false)
    var now: Date
    let account = Account(name: "Everyday Savings", currencyCode: "INR", openingBalance: 100_000)
    let fund = Account(name: "Long Term Fund", currencyCode: "INR", sortOrder: 1)
    let housing = TransactionCategory(name: "Housing", kind: .expense)
    let updates = LedgerUpdates()
    /// The app settings the catch-up notice is kept in: each `feature()` is a new launch over them (D338.6).
    let notices = InMemoryScheduledCatchUpNoticeStore()
    static let zone = "Asia/Kolkata"

    init(today: CalendarDay = CalendarDay(year: 2026, month: 10, day: 20)) throws {
        now = Self.date(today)
        try repository.saveAccount(account)
        try repository.saveAccount(fund)
        try repository.saveCategory(housing)
    }

    static func date(_ day: CalendarDay, hour: Int = 10) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour))!
    }

    var useCases: ScheduledScreenUseCases {
        let defaults = DefaultScheduledUseCases(
            repository: repository,
            now: { [unowned self] in self.now },
            timeZone: { TimeZone(identifier: Self.zone)! },
        )
        return ScheduledScreenUseCases(
            load: defaults,
            manage: defaults,
            catchUp: defaults,
            notices: ScheduledCatchUpNotices(store: notices),
        )
    }

    func feature() -> ScheduledFeature {
        ScheduledFeature(useCases: useCases, updates: updates, locale: Locale(identifier: "en_IN"))
    }

    /// A list like `feature.makeList()`, but on the given platform rather than the one the tests run on, for tests
    /// that read platform-specific wording (D334.1).
    func list(_ feature: ScheduledFeature, platform: ScheduledPlatform) -> ScheduledListViewModel {
        ScheduledListViewModel(
            useCases: feature.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: platform,
        ) { [weak updates] in updates?.changed() }
    }

    func item(_ name: String, day: Int, automatic: Bool = false, month: Int = 8) -> ScheduledItem {
        ScheduledItem(
            amount: 1_200,
            accountID: account.id,
            categoryID: housing.id,
            details: name,
            startDay: CalendarDay(year: 2026, month: month, day: day),
            processesAutomatically: automatic,
            timeZoneID: Self.zone,
            createdAt: now,
        )
    }

    func add(_ items: ScheduledItem...) throws {
        for item in items {
            let created = CalendarDay(year: 2026, month: 7, day: 1)
            try repository.saveScheduledItem(item, today: created, now: Self.date(created))
        }
    }

    var recorded: [Transaction] {
        (try? repository.transactions().filter { $0.scheduledTemplateID != nil }) ?? []
    }
}

@MainActor
@Suite("Scheduled screens (#26)")
struct ScheduledViewModelTests {
    @Test("S76–S78: one overdue row per missed occurrence, and the hint counts them")
    func overdueHint() throws {
        let scene = try ScheduledScene()
        let gym = scene.item("Gym", day: 18)
        try scene.add(scene.item("Electricity", day: 15), gym, scene.item("Phone Plan", day: 20))
        let feature = scene.feature()
        feature.catchUp(atLaunch: true)
        let list = scene.list(feature, platform: .iOS)
        list.load()
        #expect(list.overdueRows.count == 8)
        #expect(list.dueTodayRows.map(\.title) == ["Phone Plan"])
        #expect(list.overdueHint == "8 overdue payments need you. Tap one to pay or skip it.")
        #expect(feature.plannedItemCounts() == PlannedItemCounts(scheduledItemCount: 3, overdueOccurrenceCount: 8))
        let gymAugust = try #require(list.overdueRows.first { $0.title == "Gym" })
        list.payNow(gymAugust)
        #expect(list.overdueHint == "7 overdue payments need you. Tap one to pay or skip it.")
        for row in list.overdueRows.dropLast() {
            list.payNow(row)
        }
        #expect(list.overdueHint == "1 overdue payment needs you. Tap it to pay or skip it.")
        // The Mac shows the first sentence only (D334.1).
        let mac = ScheduledListViewModel(
            useCases: scene.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: .macOS,
        )
        mac.load()
        #expect(mac.overdueHint == "1 overdue payment needs you.")
        #expect(
            list.overdueHeader == "Overdue" && list.dueTodayHeader == "Due Today" && list.upcomingHeader == "Upcoming"
        )
    }

    @Test("S76–S78 on the Mac: the same overdue rows, and the hint's first sentence only (D334.1)")
    func overdueHintOnTheMac() throws {
        let scene = try ScheduledScene()
        let gym = scene.item("Gym", day: 18)
        try scene.add(scene.item("Electricity", day: 15), gym, scene.item("Phone Plan", day: 20))
        let feature = scene.feature()
        feature.catchUp(atLaunch: true)
        let list = scene.list(feature, platform: .macOS)
        list.load()
        #expect(list.overdueRows.count == 8)
        #expect(list.dueTodayRows.map(\.title) == ["Phone Plan"])
        #expect(list.overdueHint == "8 overdue payments need you.")
        let gymAugust = try #require(list.overdueRows.first { $0.title == "Gym" })
        list.payNow(gymAugust)
        #expect(list.overdueHint == "7 overdue payments need you.")
        for row in list.overdueRows.dropLast() {
            list.payNow(row)
        }
        #expect(list.overdueHint == "1 overdue payment needs you.")
        #expect(
            list.overdueHeader == "Overdue" && list.dueTodayHeader == "Due Today" && list.upcomingHeader == "Upcoming"
        )
    }

    @Test("Catch-up records automatic items before the badge, tells every window once, and never twice")
    func catchUpOnce() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Rent", day: 1, automatic: true))
        let feature = scene.feature()
        let first = try #require(feature.catchUp(atLaunch: true))
        #expect(first.posted.count == 3)
        #expect(scene.updates.revision == 1)
        #expect(feature.plannedItemCounts().overdueOccurrenceCount == 0)
        let second = try #require(feature.catchUp(atLaunch: false))
        #expect(second.posted.isEmpty)
        #expect(scene.updates.revision == 1)
        // Another launch's feature over the same store records nothing more.
        scene.feature().catchUp(atLaunch: true)
        #expect(scene.recorded.count == 3)
    }

    @Test("Pay Now on the same occurrence from two windows records it once")
    func twoWindows() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let feature = scene.feature()
        let first = feature.makeList()
        let second = feature.makeList()
        first.load()
        second.load()
        let row = try #require(first.overdueRows.first)
        first.payNow(row)
        second.payNow(try #require(second.overdueRows.first))
        #expect(scene.recorded.count == 1)
        #expect(first.alert == nil && second.alert == nil)
    }

    @Test("Skip asks first, then settles the occurrence without recording anything")
    func skip() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let list = scene.list(scene.feature(), platform: .iOS)
        list.load()
        let row = try #require(list.overdueRows.first)
        list.confirmSkip(row)
        #expect(list.confirmation?.title == "Skip 18 Oct Gym?")
        #expect(
            list.confirmation?.message
                == "Nothing is recorded for 18 Oct. The next due date stays on the schedule: 18 Nov 2026."
        )
        #expect(list.confirmation?.confirmTitle == "Skip This Occurrence")
        #expect(list.overdueRows.count == 1)
        list.confirm()
        #expect(list.overdueRows.isEmpty)
        #expect(scene.recorded.isEmpty)
        #expect(list.upcomingRows.count == 1)
    }

    @Test("Skip on the Mac asks first with a plain Skip button, then settles the occurrence (D334.1)")
    func skipOnTheMac() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let list = scene.list(scene.feature(), platform: .macOS)
        list.load()
        let row = try #require(list.overdueRows.first)
        list.confirmSkip(row)
        #expect(list.confirmation?.title == "Skip 18 Oct Gym?")
        #expect(
            list.confirmation?.message
                == "Nothing is recorded for 18 Oct. The next due date stays on the schedule: 18 Nov 2026."
        )
        #expect(list.confirmation?.confirmTitle == "Skip")
        list.confirm()
        #expect(list.overdueRows.isEmpty)
        #expect(scene.recorded.isEmpty)
        #expect(list.upcomingRows.count == 1)
    }

    @Test("Rows read the repeat, Auto and the account, and an overdue row its date")
    func rowText() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let list = scene.feature().makeList()
        list.load()
        let row = try #require(list.overdueRows.first)
        #expect(row.detail == "Monthly · Everyday Savings")
        #expect(row.dateText == "Overdue · 18 Oct")
        #expect(row.amount == "\u{2212}₹1,200.00")
        #expect(row.tone == .negative)
    }

    @Test("D24: the form previews 31 Jan, 28 Feb (last day), 31 Mar, 30 Apr (last day) and 31 May")
    func monthEndPreview() throws {
        let scene = try ScheduledScene()
        let list = scene.feature().makeList()
        list.load()
        list.openNew()
        let form = try #require(list.form)
        form.startDay = CalendarDay(year: 2027, month: 1, day: 31)
        form.frequency = .month
        #expect(form.preview.map(\.note) == [nil, "last day", nil, "last day", nil])
        #expect(form.preview.first?.date == "31 January 2027")
        #expect(form.previewFootnote?.contains("31st") == true)
    }

    @Test("The form checks the amount and the end date, then saves; editing keeps what was recorded")
    func formSave() throws {
        let scene = try ScheduledScene()
        let list = scene.feature().makeList()
        list.load()
        list.openNew()
        let form = try #require(list.form)
        form.details = "Rent"
        form.startDay = CalendarDay(year: 2026, month: 8, day: 1)
        #expect(!form.save())
        #expect(form.amountError == "Enter an amount above zero.")
        form.amountText = "25,000.005"
        #expect(!form.save())
        #expect(form.amountError == "INR amounts can have up to 2 decimal places.")
        form.amountText = "lots"
        #expect(!form.save())
        #expect(form.amountError == "Enter an amount like 1,25,000.00.")
        form.amountText = "25,000"
        form.hasEnd = true
        form.endDay = CalendarDay(year: 2026, month: 7, day: 1)
        #expect(!form.save())
        #expect(form.formError == "Pick an end date on or after the start date.")
        form.hasEnd = false
        form.processesAutomatically = true
        #expect(form.save())
        // Created on 20 Oct: the past start only sets the anchor, so Aug–Oct aren't recorded (D336.2).
        _ = try scene.useCases.catchUp.catchUp(atLaunch: true)
        list.load()
        #expect(scene.recorded.isEmpty)
        #expect(list.overdueRows.isEmpty)
        #expect(list.upcomingRows.first?.dateText == "1 Nov")
        // Opened again on 2 Dec: 1 Nov and 1 Dec are recorded.
        scene.now = ScheduledScene.date(CalendarDay(year: 2026, month: 12, day: 2))
        _ = try scene.useCases.catchUp.catchUp(atLaunch: true)
        list.load()
        #expect(scene.recorded.count == 2)
        let id = try #require(list.upcomingRows.first?.itemID)
        list.openEditor(id)
        let edit = try #require(list.form)
        edit.amountText = "26,000"
        #expect(edit.save())
        let stored = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(stored.occurrences.count == 2)
        #expect(stored.amount == 26_000)
        #expect(scene.recorded.allSatisfy { $0.amount == 25_000 })
    }

    @Test("Delete asks first; the item goes and its transactions stay")
    func delete() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Rent", day: 1, automatic: true))
        let feature = scene.feature()
        feature.catchUp(atLaunch: true)
        let list = feature.makeList()
        list.load()
        let id = try #require(list.upcomingRows.first?.itemID)
        list.confirmDelete(id)
        #expect(list.confirmation?.title == "Delete “Rent”?")
        #expect(list.confirmation?.message == "Transactions it already recorded are kept. This can’t be undone.")
        #expect(list.confirmation?.isDestructive == true)
        list.confirm()
        #expect(list.isEmpty)
        #expect(scene.recorded.count == 3)
    }

    @Test("A transfer picks a different account in the same currency, and has no category or payee")
    func transfer() throws {
        let scene = try ScheduledScene()
        let list = scene.feature().makeList()
        list.load()
        list.openNew()
        let form = try #require(list.form)
        form.categoryID = scene.housing.id
        form.type = .transfer
        #expect(form.transferAccountID == scene.fund.id)
        #expect(form.categoryID == nil)
        #expect(!form.showsCategory)
        form.amountText = "10,000"
        #expect(form.save())
        list.load()
        #expect(list.dueTodayRows.first?.title == "To Long Term Fund", "It starts today")
        #expect(list.dueTodayRows.first?.tone == .transfer)
    }

    @Test("D334: the form's titles, Repeat choices, stepper phrase and Ends choices")
    func formCopy() throws {
        let scene = try ScheduledScene()
        let list = scene.feature().makeList()
        list.load()
        list.openNew()
        let form = try #require(list.form)
        #expect(form.title == "New Scheduled Item")
        #expect(form.confirmTitle == "Add")
        #expect(
            ScheduledFrequency.allCases.map(form.frequencyName) == ["Never", "Daily", "Weekly", "Monthly", "Yearly"]
        )
        form.frequency = .month
        #expect(form.intervalText == "Monthly")
        form.interval = 2
        #expect(form.intervalText == "Every 2 months")
        form.frequency = .week
        #expect(form.intervalText == "Every 2 weeks")
        #expect(
            [form.endsLabel, form.endsNeverTitle, form.endsOnDateTitle, form.endDateLabel] == [
                "Ends", "Never", "On Date", "End Date",
            ]
        )
        #expect(list.addTitle == "Add Scheduled Item")
        #expect(list.emptyTitle == "Nothing Scheduled")
        #expect(list.emptyMessage == "Add rent, salary or subscriptions once. They can be recorded for you.")
        form.amountText = "1,200"
        #expect(form.save())
        list.load()
        list.openEditor(try #require(list.dueTodayRows.first?.itemID))
        #expect(list.form?.title == "Edit Scheduled Item")
    }

    @Test("D334.12: a currency with no decimal places, and one with one, use whole phrases")
    func decimalErrors() throws {
        let scene = try ScheduledScene()
        let yen = Account(name: "Tokyo Wallet", currencyCode: "JPY", sortOrder: 2)
        try scene.repository.saveAccount(yen)
        let list = scene.feature().makeList()
        list.load()
        list.openNew()
        let form = try #require(list.form)
        form.accountID = yen.id
        form.amountText = "1,200.5"
        #expect(!form.save())
        #expect(form.amountError == "JPY amounts have no decimal places.")
        #expect(ScheduledText.tooManyDecimals(1, currencyCode: "MGA") == "MGA amounts can have up to 1 decimal place.")
    }

    @Test("D334.10: the Mac menu takes ellipses on items that ask first; iOS never does")
    func menuTitles() throws {
        let scene = try ScheduledScene()
        let mac = ScheduledListViewModel(useCases: scene.useCases, platform: .macOS)
        #expect(
            [mac.payNowTitle, mac.skipMenuTitle, mac.editMenuTitle, mac.deleteMenuTitle] == [
                "Pay Now", "Skip This Occurrence…", "Edit…", "Delete Scheduled Item…",
            ]
        )
        let phone = ScheduledListViewModel(useCases: scene.useCases, platform: .iOS)
        #expect(
            [phone.payNowTitle, phone.skipMenuTitle, phone.editMenuTitle, phone.deleteMenuTitle] == [
                "Pay Now", "Skip This Occurrence", "Edit", "Delete",
            ]
        )
        #expect(phone.skipTitle == "Skip This Occurrence")
    }

    @Test("D334.8: the Mac Skip button, and the message when no due date follows")
    func skipLast() throws {
        let scene = try ScheduledScene()
        var once = scene.item("Electricity", day: 5, month: 10)
        once.repeatRule = .never
        try scene.add(once)
        let mac = ScheduledListViewModel(
            useCases: scene.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: .macOS,
        )
        mac.load()
        mac.confirmSkip(try #require(mac.overdueRows.first))
        #expect(mac.confirmation?.title == "Skip 5 Oct Electricity?")
        #expect(mac.confirmation?.message == "Nothing is recorded for 5 Oct. There are no due dates after it.")
        #expect(mac.confirmation?.confirmTitle == "Skip")
    }

    @Test("D334.13 and D334.5: a completed item reads Ended and its last due date; Ends reads Never or On a date")
    func endedAndEnds() throws {
        let scene = try ScheduledScene()
        var gym = scene.item("Gym", day: 5, month: 8)
        gym.endDay = CalendarDay(year: 2026, month: 10, day: 5)
        let rent = scene.item("Rent", day: 1, month: 8)
        try scene.add(gym, rent)
        let list = scene.feature().makeList()
        list.load()
        for row in list.overdueRows where row.itemID == gym.id {
            list.payNow(row)
        }
        let ended = try #require(list.detail(gym.id))
        #expect(ended.next == "Ended 5 Oct")
        #expect(ended.facts.first { $0.label == "Ends" }?.value == "On 5 Oct 2026")
        #expect(list.detail(rent.id)?.facts.first { $0.label == "Ends" }?.value == "Never")
        #expect(list.completedCount == "1")
    }

    @Test("Only the Scheduled screen on top presents the sheet, confirmations and alerts")
    func presenter() throws {
        let scene = try ScheduledScene()
        let list = scene.feature().makeList()
        let id = UUID()
        #expect(list.presenter == .list)
        list.screenAppeared(.list)
        // A push may report either side first.
        list.screenAppeared(.item(id))
        list.screenDisappeared(.list)
        #expect(list.presenter == .item(id))
        list.screenAppeared(.list)
        list.screenDisappeared(.item(id))
        #expect(list.presenter == .list)
        list.screenAppeared(.completed)
        #expect(list.presenter == .completed)
        list.screenDisappeared(.completed)
        #expect(list.presenter == .list)
    }
}

import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// S33, D353.3, D354.2: tapping a reminder opens its item; a paid or skipped occurrence opens the item screen
/// without its Pay and Skip, and a deleted item leaves the Scheduled list. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Scheduled reminder taps (#26 S33, D354.2)")
struct ScheduledReminderTapTests {
    private let today = CalendarDay(year: 2026, month: 10, day: 20)

    @Test("A tap waits until a window takes it, once; the latest tap wins")
    func tapWaitsAndIsTakenOnce() {
        let taps = ScheduledReminderTaps()
        #expect(taps.take(for: nil) == nil)
        let first = UUID()
        let second = UUID()
        taps.tapped(itemID: first)
        taps.tapped(itemID: second)
        #expect(taps.pending?.itemID == second)
        #expect(taps.take(for: nil)?.itemID == second)
        #expect(taps.pending == nil)
        #expect(taps.take(for: nil) == nil)
    }

    @Test("Two taps on the same item's reminder are two taps")
    func sameItemTwice() {
        let taps = ScheduledReminderTaps()
        let item = UUID()
        taps.tapped(itemID: item)
        let first = taps.take(for: nil)
        taps.tapped(itemID: item)
        let second = taps.take(for: nil)
        #expect(first?.itemID == second?.itemID)
        #expect(first != second)
    }

    @Test("The feature keeps one set of taps for every window")
    func featureOwnsTaps() throws {
        let scene = try ScheduledScene()
        let feature = scene.feature()
        feature.reminderTaps.tapped(itemID: UUID())
        #expect(feature.reminderTaps.pending != nil)
    }

    @Test("D353.3: a due occurrence's reminder opens its item, with Pay and Skip for that occurrence")
    func opensDueItem() throws {
        let scene = try ScheduledScene()
        let electricity = scene.item("Electricity", day: 20, month: 10)
        try scene.add(electricity)
        let feature = scene.feature()
        #expect(feature.itemOpened(by: ScheduledReminderTap(itemID: electricity.id)) == electricity.id)
        let list = scene.list(feature, platform: .iOS)
        list.loadIfNeeded()
        #expect(list.detail(electricity.id)?.due.map(\.occurrence) == [today])
    }

    @Test("D354.2: once paid or skipped, it opens the item screen with Next Due and no Pay or Skip for it")
    func paidOrSkippedOpensItem() throws {
        let scene = try ScheduledScene()
        let paid = scene.item("Electricity", day: 20, month: 10)
        let skipped = scene.item("Phone Plan", day: 20, month: 10)
        try scene.add(paid, skipped)
        let feature = scene.feature()
        try feature.useCases.manage.payNow(itemID: paid.id, occurrence: today)
        try feature.useCases.manage.skip(itemID: skipped.id, occurrence: today)
        let list = scene.list(feature, platform: .macOS)
        list.loadIfNeeded()
        for item in [paid, skipped] {
            #expect(feature.itemOpened(by: ScheduledReminderTap(itemID: item.id)) == item.id)
            let detail = try #require(list.detail(item.id))
            #expect(detail.due.isEmpty)
            #expect(!detail.next.isEmpty)
            #expect(list.alert == nil)
        }
    }

    @Test("D354.2: a deleted or unknown item's reminder leaves the Scheduled list, with no alert")
    func deletedStaysOnList() throws {
        let scene = try ScheduledScene()
        let electricity = scene.item("Electricity", day: 20, month: 10)
        try scene.add(electricity)
        let feature = scene.feature()
        try feature.useCases.manage.delete(id: electricity.id)
        let list = scene.list(feature, platform: .iOS)
        list.loadIfNeeded()
        #expect(feature.itemOpened(by: ScheduledReminderTap(itemID: electricity.id)) == nil)
        #expect(feature.itemOpened(by: ScheduledReminderTap(itemID: UUID())) == nil)
        #expect(list.alert == nil)
    }

    @Test("Tester 6419979176: a Mac cold tap sets the Scheduled path to its item at once, read fresh, once")
    func macColdTapPathHasItem() throws {
        let scene = try ScheduledScene()
        let electricity = scene.item("Electricity", day: 20, month: 10)
        try scene.add(electricity)
        let feature = scene.feature()
        feature.reminderTaps.tapped(itemID: electricity.id)
        let tap = try #require(feature.reminderTaps.take(for: nil))
        let item = feature.itemOpened(by: tap)
        #expect(item == electricity.id)
        let path = ScheduledReminderRouting.macPath([], item: item, sheets: .afterClosing)
        #expect(path == [.item(electricity.id)])
        #expect(feature.reminderTaps.take(for: nil) == nil)
    }

    @Test("Mac: with sheets closed the path is just the item; a deleted item leaves the list (D354.2)")
    func macPathAfterClosing() {
        let phone = UUID()
        let gym = UUID()
        let path = ScheduledReminderRouting.macPath([.item(phone), .completed], item: gym, sheets: .afterClosing)
        #expect(path == [.item(gym)])
        #expect(ScheduledReminderRouting.macPath([.item(phone)], item: nil, sheets: .afterClosing).isEmpty)
    }

    @Test(
        "Mac, dirty sheet on Scheduled: the screen showing it stays and the item goes on top (UI Designer 6402418696)"
    )
    func macPathUnderneathKeepsSheetScreen() {
        let phone = UUID()
        let gym = UUID()
        #expect(
            ScheduledReminderRouting.macPath([.item(phone)], item: gym, sheets: .underneath) == [
                .item(phone), .item(gym),
            ]
        )
        #expect(ScheduledReminderRouting.macPath([.item(gym)], item: gym, sheets: .underneath) == [.item(gym)])
        #expect(ScheduledReminderRouting.macPath([.item(phone)], item: nil, sheets: .underneath) == [.item(phone)])
    }

    @Test("Tester 6421333811: a dirty-sheet tap on Phone Plan, then its replay, puts the item on top once")
    func macPathDirtySheetTapReplayOnce() {
        let phone = UUID()
        let electricity = UUID()
        let tapped = ScheduledReminderRouting.macPath([.item(phone)], item: electricity, sheets: .underneath)
        #expect(tapped == [.item(phone), .item(electricity)])
        // The same tap applied again, as a replay when the sheet closes, changes nothing.
        #expect(ScheduledReminderRouting.macPath(tapped, item: electricity, sheets: .underneath) == tapped)
    }

    @Test("Tester 6418798177: an iOS cold tap puts Scheduled and its item on the path at once, read fresh, once")
    func iosColdTapPathHasItem() throws {
        let scene = try ScheduledScene()
        let electricity = scene.item("Electricity", day: 20, month: 10)
        try scene.add(electricity)
        let feature = scene.feature()
        feature.reminderTaps.tapped(itemID: electricity.id)
        let tap = try #require(feature.reminderTaps.take(for: nil))
        let item = feature.itemOpened(by: tap).map { AccountsRoute.scheduled(.item($0)) }
        let path = ScheduledReminderRouting.path([], scheduled: .home(.scheduled), item: item, sheets: .afterClosing)
        #expect(path == [.home(.scheduled), .scheduled(.item(electricity.id))])
        #expect(feature.reminderTaps.take(for: nil) == nil)
    }
}

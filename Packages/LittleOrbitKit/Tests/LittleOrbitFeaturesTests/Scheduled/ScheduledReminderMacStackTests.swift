import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The Mac Scheduled detail's `NavigationStack(path: $scheduledPath)`, as SwiftUI drives the screens' callbacks
/// (Tester2 6425404539). A value that leaves the path reports its screen gone, and one added at a new index reports
/// its screen up. An item replaced by another item at the same index keeps its `ScheduledItemView` and only changes
/// its `itemID`, so neither callback fires and the view's `onChange(of: itemID)` reports the swap instead. The Mac
/// may or may not report the list going under a push and coming back after the last Back, so both are run.
@MainActor
private struct MacScheduledStack {
    let list: ScheduledListViewModel
    let listDisappearsUnderPush: Bool
    private(set) var path: [ScheduledRoute] = []

    init(_ list: ScheduledListViewModel, listDisappearsUnderPush: Bool) {
        self.list = list
        self.listDisappearsUnderPush = listDisappearsUnderPush
        list.screenAppeared(.list)
        list.load()
    }

    private static func screen(_ route: ScheduledRoute) -> ScheduledScreen {
        switch route {
        case .item(let id): .item(id)
        case .completed: .completed
        }
    }

    mutating func set(_ new: [ScheduledRoute]) {
        let old = path
        path = new
        if old.isEmpty, !new.isEmpty, listDisappearsUnderPush {
            list.screenDisappeared(.list)
        }
        for route in old.dropFirst(new.count).reversed() {
            list.screenDisappeared(Self.screen(route))
        }
        for (before, after) in zip(old, new) where before != after {
            if case .item(let oldID) = before, case .item(let newID) = after {
                list.screenChanged(from: .item(oldID), to: .item(newID))
            } else {
                list.screenDisappeared(Self.screen(before))
                list.screenAppeared(Self.screen(after))
            }
        }
        for route in new.dropFirst(old.count) {
            list.screenAppeared(Self.screen(route))
        }
        if !old.isEmpty, new.isEmpty, listDisappearsUnderPush {
            list.screenAppeared(.list)
        }
    }

    /// A row click on the list, or a link on an item screen.
    mutating func push(_ item: UUID) {
        set(path + [.item(item)])
    }

    mutating func back() {
        set(Array(path.dropLast()))
    }

    /// A tapped reminder, as `AccountsSplitView.open` applies it.
    mutating func tap(_ item: UUID, sheets: SheetNavigation = .afterClosing) {
        set(ScheduledReminderRouting.macPath(path, item: item, sheets: sheets))
    }

    /// The form a screen's `.scheduledSheets` shows: only the presenter's binding returns it.
    func presentedForm(on screen: ScheduledScreen) -> ScheduledFormViewModel? {
        list.presenter == screen ? list.form : nil
    }
}

/// #209 case 3 (Tester2 6425404539): after a reminder tap swaps one item screen for another on the Mac, the list's
/// + Add and Edit… and the item's own Edit… must present. Made-up data.
@MainActor
@Suite("Scheduled reminder taps on the Mac stack (#209 case 3)")
struct ScheduledReminderMacStackTests {
    private static let orderings = [false, true]

    private struct Items {
        let phone: ScheduledItem
        let electricity: ScheduledItem
        let gym: ScheduledItem
    }

    private func scene() throws -> (ScheduledScene, Items) {
        let scene = try ScheduledScene()
        let items = Items(
            phone: scene.item("Phone Plan", day: 25, month: 10),
            electricity: scene.item("Electricity", day: 20, month: 10),
            gym: scene.item("Gym", day: 18, month: 10),
        )
        try scene.add(items.phone, items.electricity, items.gym)
        return (scene, items)
    }

    /// Back on the list: + Add, then the row's Edit…, each present there and nowhere else.
    private func expectListPresents(_ stack: MacScheduledStack, _ item: UUID) {
        #expect(stack.path.isEmpty)
        #expect(stack.list.visibleScreens == [.list])
        stack.list.openNew()
        #expect(stack.presentedForm(on: .list)?.isNew == true)
        stack.list.form = nil
        stack.list.openEditor(item)
        #expect(stack.presentedForm(on: .list)?.isNew == false)
        stack.list.form = nil
    }

    /// The tap-opened screen's own Edit… presents on it, and Cancel closes it.
    private func expectItemPresents(_ stack: MacScheduledStack, _ item: UUID) {
        #expect(stack.list.presenter == .item(item))
        stack.list.openEditor(item)
        #expect(stack.presentedForm(on: .item(item)) != nil)
        #expect(stack.presentedForm(on: .list) == nil)
        stack.list.form = nil
    }

    @Test("Case 3: a clean Edit sheet on Phone Plan, a tap for Electricity, then its Edit…, Back and + Add present")
    func cleanSheetTapThenEditBackAndAdd() throws {
        let (scene, items) = try scene()
        for listDisappears in Self.orderings {
            var stack = MacScheduledStack(
                scene.list(scene.feature(), platform: .macOS),
                listDisappearsUnderPush: listDisappears,
            )
            stack.push(items.phone.id)
            stack.list.openEditor(items.phone.id)
            #expect(stack.presentedForm(on: .item(items.phone.id)) != nil)
            // The clean form closes for the tap, and Electricity replaces Phone Plan on the path.
            stack.list.form = nil
            stack.tap(items.electricity.id)
            #expect(stack.path == [.item(items.electricity.id)])
            expectItemPresents(stack, items.electricity.id)
            stack.back()
            expectListPresents(stack, items.phone.id)
        }
    }

    @Test(
        "Check B: no sheet, a tap on Gym's screen opens Electricity in place; one Back reaches the list and + Add works"
    )
    func tapWithoutSheetThenBackAndAdd() throws {
        let (scene, items) = try scene()
        for listDisappears in Self.orderings {
            var stack = MacScheduledStack(
                scene.list(scene.feature(), platform: .macOS),
                listDisappearsUnderPush: listDisappears,
            )
            stack.push(items.gym.id)
            stack.tap(items.electricity.id)
            #expect(stack.list.presenter == .item(items.electricity.id))
            stack.back()
            expectListPresents(stack, items.gym.id)
            // A row push and Back still work after it.
            stack.push(items.phone.id)
            expectItemPresents(stack, items.phone.id)
            stack.back()
            expectListPresents(stack, items.phone.id)
        }
    }

    @Test("A second tap for the same item keeps its screen; one Back reaches the list")
    func secondTapSameItem() throws {
        let (scene, items) = try scene()
        for listDisappears in Self.orderings {
            var stack = MacScheduledStack(
                scene.list(scene.feature(), platform: .macOS),
                listDisappearsUnderPush: listDisappears,
            )
            stack.push(items.phone.id)
            stack.tap(items.electricity.id)
            stack.tap(items.electricity.id)
            #expect(stack.path == [.item(items.electricity.id)])
            #expect(stack.list.visibleScreens.filter { $0 != .list } == [.item(items.electricity.id)])
            expectItemPresents(stack, items.electricity.id)
            stack.back()
            expectListPresents(stack, items.electricity.id)
        }
    }

    @Test("A second tap for another item swaps again; its Edit…, then Back and + Add present")
    func secondTapOtherItem() throws {
        let (scene, items) = try scene()
        for listDisappears in Self.orderings {
            var stack = MacScheduledStack(
                scene.list(scene.feature(), platform: .macOS),
                listDisappearsUnderPush: listDisappears,
            )
            stack.push(items.phone.id)
            stack.tap(items.electricity.id)
            stack.tap(items.gym.id)
            #expect(stack.path == [.item(items.gym.id)])
            #expect(stack.list.visibleScreens.filter { $0 != .list } == [.item(items.gym.id)])
            expectItemPresents(stack, items.gym.id)
            stack.back()
            expectListPresents(stack, items.gym.id)
            // A tap from the list itself is a push at a new index, as before.
            stack.tap(items.phone.id)
            expectItemPresents(stack, items.phone.id)
            stack.back()
            expectListPresents(stack, items.phone.id)
        }
    }

    @Test("A screen changed to the screen it already shows changes nothing")
    func screenChangedToItselfKeepsOrder() throws {
        let scene = try ScheduledScene()
        let list = scene.list(scene.feature(), platform: .macOS)
        let gym = UUID()
        list.screenAppeared(.list)
        list.screenAppeared(.item(gym))
        list.screenAppeared(.completed)
        list.screenChanged(from: .item(gym), to: .item(gym))
        #expect(list.visibleScreens == [.list, .item(gym), .completed])
        #expect(list.presenter == .completed)
    }
}

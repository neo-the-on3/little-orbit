import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The Mac Scheduled Table's sections, rows and footer (#26, D340.6, D340.13, D355, D356). Made-up data; today is
/// 20 Oct 2026. Every list here is the Mac's, passed explicitly.
@MainActor
@Suite("Mac Scheduled Table (#26, D340.13, D355)")
struct ScheduledTableTests {
    private static let locale = Locale(identifier: "en_IN")

    private func macList(_ scene: ScheduledScene) -> ScheduledListViewModel {
        let list = ScheduledListViewModel(useCases: scene.useCases, locale: Self.locale, platform: .macOS)
        list.load()
        return list
    }

    private func status(_ list: ScheduledListViewModel) -> [String: String] {
        Dictionary(uniqueKeysWithValues: list.tableSections.flatMap(\.rows).map { ($0.name, $0.status) })
    }

    @Test("S76: sections Overdue, Due Today and Upcoming with no counts, one row per overdue occurrence")
    func sections() throws {
        let scene = try ScheduledScene()
        try scene.add(
            scene.item("Electricity", day: 15),
            scene.item("Gym", day: 18),
            scene.item("Phone Plan", day: 20),
            scene.item("Rent", day: 1, month: 11),
        )
        let list = macList(scene)
        let sections = list.tableSections
        #expect(sections.map(\.title) == ["Overdue", "Due Today", "Upcoming"])
        let overdue = sections[0].rows
        #expect(overdue.count == 8)
        #expect(overdue.map(\.name).prefix(3) == ["Electricity", "Gym", "Phone Plan"])
        #expect(overdue.map(\.due).prefix(2) == ["15 Aug", "18 Aug"])
        #expect(sections[1].rows.map(\.name) == ["Phone Plan"])
        #expect(sections[2].rows.map(\.due) == ["1 Nov"])
        // Each overdue row acts on its own occurrence, and the lookup finds it.
        #expect(Set(overdue.map(\.id)).count == 8)
        #expect(overdue.allSatisfy { $0.row.canSettle && list.tableRow(id: $0.id) == $0 })
    }

    @Test("D355.2: overdue reads its days, automatic or not, as whole-phrase plurals")
    func overdueStatus() throws {
        let scene = try ScheduledScene()
        try scene.add(
            scene.item("Electricity", day: 15, month: 10),
            scene.item("Gym", day: 19, month: 10),
            scene.item("Rent", day: 17, automatic: true, month: 10),
        )
        let status = status(macList(scene))
        #expect(status["Electricity"] == "Overdue · 5 days")
        #expect(status["Gym"] == "Overdue · 1 day")
        // An automatic item is overdue only after Undo Pay (D344.1); it reads like a manual one.
        #expect(status["Rent"] == "Overdue · 3 days")
    }

    @Test("D355.2, D356.1: due today names Automatic, or the Reminder Time for a manual item that notifies")
    func dueTodayStatus() throws {
        let scene = try ScheduledScene()
        var notified = scene.item("Phone Plan", day: 20, month: 10)
        notified.notifiesWhenDue = true
        var both = scene.item("Rent", day: 20, automatic: true, month: 10)
        both.notifiesWhenDue = true
        try scene.add(
            scene.item("Water", day: 20, month: 10),
            scene.item("Salary", day: 20, automatic: true, month: 10),
            notified,
            both,
        )
        let list = macList(scene)
        let status = status(list)
        #expect(status["Water"] == "Due today")
        #expect(status["Salary"] == "Due today · Automatic")
        #expect(status["Rent"] == "Due today · Automatic")
        #expect(status["Phone Plan"] == "Due today · \(list.reminderTimeText)")
        #expect(list.reminderTimeText.contains("9:00"))
        list.reminderTime = DateComponents(hour: 7, minute: 45)
        #expect(self.status(list)["Phone Plan"] == "Due today · \(list.reminderTimeText)")
        #expect(list.reminderTimeText.contains("7:45"))
    }

    @Test("D355.1, D355.2: upcoming is blank for a plain manual item, else its mode")
    func upcomingStatus() throws {
        let scene = try ScheduledScene()
        var notified = scene.item("Phone Plan", day: 5, month: 11)
        notified.notifiesWhenDue = true
        var both = scene.item("Rent", day: 1, automatic: true, month: 11)
        both.notifiesWhenDue = true
        try scene.add(
            scene.item("Water", day: 3, month: 11),
            scene.item("Salary", day: 2, automatic: true, month: 11),
            notified,
            both,
        )
        let list = macList(scene)
        let status = status(list)
        #expect(status["Water"] == "")
        #expect(status["Salary"] == "Automatic")
        #expect(status["Rent"] == "Automatic + notify")
        #expect(status["Phone Plan"] == "Notify \(list.reminderTimeText)")
    }

    @Test("D355.3: Due shows the year only outside this year, with the long Repeat form")
    func dueYear() throws {
        let scene = try ScheduledScene()
        var insurance = scene.item("Home Insurance", day: 15, month: 1)
        insurance.startDay = CalendarDay(year: 2027, month: 1, day: 15)
        insurance.repeatRule = .yearly
        try scene.add(insurance, scene.item("Rent", day: 15, month: 11))
        let rows = macList(scene).tableSections.flatMap(\.rows)
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) })
        #expect(byName["Home Insurance"]?.due == "15 Jan 2027")
        #expect(byName["Home Insurance"]?.repeatText == "Yearly on 15 January")
        #expect(byName["Rent"]?.due == "15 Nov")
        #expect(byName["Rent"]?.repeatText == "Monthly on the 15th")
        #expect(byName["Rent"]?.account == "Everyday Savings")
        #expect(byName["Rent"]?.amount.contains("1,200") == true)
        #expect(byName["Rent"]?.tone == .negative)
    }

    @Test("D355.3, D355.4: a completed row shows its last due date, keeps its rule and reads Ended")
    func completed() throws {
        let scene = try ScheduledScene()
        var gym = scene.item("Gym", day: 5, month: 8)
        gym.endDay = CalendarDay(year: 2026, month: 10, day: 5)
        var deposit = scene.item("Deposit", day: 15, month: 10)
        deposit.repeatRule = .never
        try scene.add(gym, deposit)
        let list = macList(scene)
        for row in list.tableSections.flatMap(\.rows) {
            list.payNow(row.row)
        }
        let sections = list.tableSections
        #expect(sections.map(\.title) == ["Completed"], "No count in the header (D334.2)")
        let byName = Dictionary(uniqueKeysWithValues: sections[0].rows.map { ($0.name, $0) })
        #expect(byName["Gym"]?.due == "5 Oct")
        #expect(byName["Gym"]?.repeatText == "Monthly on the 5th")
        #expect(byName["Gym"]?.status == "Ended 5 Oct")
        #expect(byName["Deposit"]?.due == "15 Oct")
        #expect(byName["Deposit"]?.repeatText == "Once")
        #expect(byName["Deposit"]?.status == "Ended 15 Oct")
        #expect(byName["Deposit"]?.row.canSettle == false)
        let id = try #require(byName["Deposit"]?.id)
        #expect(list.tableRow(id: id)?.row.itemID == deposit.id)
    }

    @Test("D356.2, D357: each long Repeat form, at an interval of 1 and of N")
    func longRepeat() throws {
        let scene = try ScheduledScene()
        func text(_ rule: ScheduleRepeat, _ year: Int, _ month: Int, _ day: Int) -> String {
            var item = scene.item("Item", day: day, month: month)
            item.startDay = CalendarDay(year: year, month: month, day: day)
            item.repeatRule = rule
            return ScheduledRepeatText.long(item, locale: Self.locale)
        }
        #expect(text(.never, 2026, 10, 24) == "Once")
        #expect(text(.daily, 2026, 10, 24) == "Daily")
        #expect(text(.every(3, .day), 2026, 10, 24) == "Every 3 days")
        // 24 Oct 2026 is a Saturday.
        #expect(text(.weekly, 2026, 10, 24) == "Weekly on Saturday")
        #expect(text(.every(2, .week), 2026, 10, 24) == "Every 2 weeks on Saturday")
        #expect(text(.monthly, 2026, 10, 15) == "Monthly on the 15th")
        #expect(text(.monthly, 2026, 10, 1) == "Monthly on the 1st")
        #expect(text(.monthly, 2026, 10, 30) == "Monthly on the 30th")
        #expect(text(.every(2, .month), 2026, 10, 22) == "Every 2 months on the 22nd")
        #expect(text(.monthly, 2026, 10, 31) == "Monthly on the last day")
        #expect(text(.every(3, .month), 2026, 10, 31) == "Every 3 months on the last day")
        #expect(text(.yearly, 2026, 3, 15) == "Yearly on 15 March")
        #expect(text(.every(2, .year), 2028, 2, 29) == "Every 2 years on 29 February")
    }

    @Test("D340.13, NB 3: the footer's counts are plurals that show their number")
    func footer() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Electricity", day: 15), scene.item("Rent", day: 1, month: 11))
        let list = macList(scene)
        #expect(list.tableFooter == "2 scheduled · 3 overdue · double-click to open · right-click for actions")
        let one = try ScheduledScene()
        try one.add(one.item("Rent", day: 1, month: 11))
        #expect(macList(one).tableFooter == "1 scheduled · double-click to open · right-click for actions")
        let empty = macList(try ScheduledScene())
        #expect(empty.tableFooter == nil)
        #expect(empty.tableSections.isEmpty)
    }

    @Test("Column titles, and iOS builds no table")
    func columnTitles() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Rent", day: 1, month: 11))
        let list = macList(scene)
        #expect(
            [
                list.dueColumn, list.nameColumn, list.repeatColumn, list.accountColumn, list.amountColumn,
                list.statusColumn,
            ]
                == ["Due", "Name", "Repeat", "Account", "Amount", "Status"]
        )
        let iOS = ScheduledListViewModel(useCases: scene.useCases, locale: Self.locale, platform: .iOS)
        iOS.load()
        #expect(iOS.tableSections.isEmpty)
        #expect(iOS.upcomingRows.first?.detail.hasPrefix("Monthly") == true, "iOS keeps the short names")
    }

    @Test("D360.2: ⌘E and Delete act only on the selected row, Delete asks first, and there's no Pay command")
    func shortcuts() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, month: 11)
        try scene.add(rent)
        let list = macList(scene)
        let id = try #require(list.tableSections.first?.rows.first?.id)
        #expect(!list.tableCommand(.edit, selection: nil))
        #expect(!list.tableCommand(.delete, selection: nil))
        #expect(!list.tableCommand(.delete, selection: "gone"))
        #expect(list.form == nil && list.confirmation == nil)
        #expect(list.tableCommand(.delete, selection: id))
        #expect(list.confirmation != nil, "Always the delete confirmation (D334.9)")
        #expect(try scene.repository.scheduleLedger().scheduledItems.count == 1, "Nothing is deleted yet")
        list.confirmation = nil
        #expect(list.tableCommand(.edit, selection: id))
        #expect(list.form?.title == "Edit Scheduled Item")
        #expect(scene.recorded.isEmpty, "No shortcut records anything")
        #expect(list.newItemTitle == "New Scheduled Item")
    }

    @Test("Tech Architect, #198: the Mac hint is shown once drawn, and again when a catch-up replaces it on screen")
    func catchUpHintReplaced() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Rent", day: 1, automatic: true))
        let feature = scene.feature()
        feature.catchUp(atLaunch: true)
        let list = scene.list(feature, platform: .macOS)
        list.screenAppeared(.list)
        list.load()
        let first = try #require(list.catchUpHint)
        #expect(scene.notices.notice()?.shown == false, "Loaded but not drawn")
        // The hint's `.task(id: hint)` runs.
        list.catchUpHintAppeared()
        #expect(scene.notices.notice()?.shown == true)
        // A new day while the list is on screen: another catch-up replaces the text in place.
        try scene.add(scene.item("Water", day: 3, automatic: true, month: 11))
        scene.now = ScheduledScene.date(CalendarDay(year: 2026, month: 11, day: 5))
        feature.catchUp(atLaunch: false)
        list.load()
        let second = try #require(list.catchUpHint)
        #expect(second != first)
        #expect(scene.notices.notice()?.shown == false, "The new part isn't drawn yet")
        // The task is keyed on the text, so it runs again and the merged hint counts as shown.
        list.catchUpHintAppeared()
        #expect(scene.notices.notice()?.shown == true)
        list.dismissCatchUpHint()
        let next = scene.list(feature, platform: .macOS)
        next.screenAppeared(.list)
        next.load()
        #expect(next.catchUpHint == nil, "The next visit doesn't show it again")
    }
}

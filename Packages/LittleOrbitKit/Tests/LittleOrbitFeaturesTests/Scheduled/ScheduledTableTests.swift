import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The Mac Scheduled Table's sections, rows and footer (#26, D340.6, D340.13). Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Mac Scheduled Table (#26, D340.13)")
struct ScheduledTableTests {
    private func macList(_ scene: ScheduledScene) -> ScheduledListViewModel {
        let list = ScheduledListViewModel(
            useCases: scene.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: .macOS,
        )
        list.load()
        return list
    }

    @Test("S76: sections Overdue, Due Today and Upcoming, one row per overdue occurrence, ordered by date")
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
        // Each overdue row acts on its own occurrence.
        #expect(Set(overdue.map(\.id)).count == 8)
        #expect(overdue.allSatisfy { $0.row.canSettle })
    }

    @Test("D340.13: Status reads “Overdue · 1 day” or “Overdue · 5 days”, then Due today and Upcoming")
    func status() throws {
        let scene = try ScheduledScene()
        try scene.add(
            scene.item("Electricity", day: 15, month: 10),
            scene.item("Gym", day: 19, month: 10),
            scene.item("Phone Plan", day: 20, month: 10),
            scene.item("Rent", day: 1, automatic: true, month: 11),
        )
        let list = macList(scene)
        let rows = list.tableSections.flatMap(\.rows)
        let status = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.status) })
        #expect(status["Electricity"] == "Overdue · 5 days")
        #expect(status["Gym"] == "Overdue · 1 day")
        #expect(status["Phone Plan"] == "Due today")
        #expect(status["Rent"] == "Upcoming · Auto")
    }

    @Test("Columns: repeat, account and a signed amount")
    func columns() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Rent", day: 1, month: 11))
        let row = try #require(macList(scene).tableSections.first?.rows.first)
        #expect(row.repeatText == "Monthly")
        #expect(row.account == "Everyday Savings")
        #expect(row.amount.contains("1,200"))
        #expect(row.tone == .negative)
    }

    @Test("D334.2: only Completed shows a count, and its rows open the item")
    func completed() throws {
        let scene = try ScheduledScene()
        var once = scene.item("Deposit", day: 15, month: 10)
        once.repeatRule = .never
        try scene.add(once)
        let list = macList(scene)
        list.payNow(try #require(list.tableSections.first?.rows.first?.row))
        let sections = list.tableSections
        #expect(sections.map(\.title) == ["Completed · 1"])
        let row = try #require(sections.first?.rows.first)
        #expect(row.due.isEmpty)
        #expect(row.status == "Completed")
        #expect(!row.row.canSettle)
        #expect(list.tableRow(id: row.id)?.row.itemID == once.id)
    }

    @Test("D340.13: the footer counts items and overdue occurrences, then how to open and act")
    func footer() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Electricity", day: 15), scene.item("Rent", day: 1, month: 11))
        let list = macList(scene)
        #expect(list.tableFooter == "2 scheduled · 3 overdue · double-click to open · right-click for actions")
        let empty = macList(try ScheduledScene())
        #expect(empty.tableFooter == nil)
        #expect(empty.tableSections.isEmpty)
    }

    @Test("Column titles")
    func columnTitles() throws {
        let list = macList(try ScheduledScene())
        #expect(
            [
                list.dueColumn, list.nameColumn, list.repeatColumn, list.accountColumn, list.amountColumn,
                list.statusColumn,
            ]
                == ["Due", "Name", "Repeat", "Account", "Amount", "Status"]
        )
    }
}

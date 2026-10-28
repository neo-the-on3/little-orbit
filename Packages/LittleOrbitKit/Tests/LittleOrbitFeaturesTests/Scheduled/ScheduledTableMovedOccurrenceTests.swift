import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The Mac Scheduled Table with an occurrence moved and changed with "This occurrence only" (#205 with #202, D45):
/// its row shows the occurrence's own due day and amount, and Pay Now, Skip and Edit act on that occurrence, by its
/// key. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Mac Scheduled Table: a moved occurrence (#205, D45)")
struct ScheduledTableMovedOccurrenceTests {
    private let key = CalendarDay(year: 2026, month: 10, day: 18)

    /// Gym, ₹1,200 monthly on the 18th from 18 Oct; its 18 Oct occurrence moved to 19 Oct at ₹1,300.
    private func movedGym() throws -> (ScheduledScene, ScheduledListViewModel) {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let item = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        var form = item.resolved(for: key)
        form.occurrences = item.occurrences
        form.amount = 1_300
        _ = try scene.useCases.manage.update(
            form,
            editing: ScheduledOccurrenceSave(
                occurrence: key,
                dueDay: CalendarDay(year: 2026, month: 10, day: 19),
                scope: .thisOccurrence,
            ),
            payee: nil,
        )
        let list = ScheduledListViewModel(
            useCases: scene.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: .macOS,
        )
        list.load()
        return (scene, list)
    }

    private func overdueRow(_ list: ScheduledListViewModel) throws -> ScheduledTableRow {
        let section = try #require(list.tableSections.first)
        #expect(section.title == "Overdue")
        return try #require(section.rows.first)
    }

    @Test("The row shows 19 Oct and ₹1,300, keyed to 18 Oct; Pay Now records ₹1,300 once")
    func payMoved() throws {
        let (scene, list) = try movedGym()
        let row = try overdueRow(list)
        #expect(row.due == "19 Oct")
        #expect(row.amount.contains("1,300"))
        #expect(row.row.occurrence == key)
        #expect(list.tableRow(id: row.id) == row)
        list.payNow(row.row)
        #expect(scene.recorded.map(\.amount) == [1_300])
        let item = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(item.occurrence(on: key)?.outcome == .posted)
    }

    @Test("Skip settles the 18 Oct occurrence and records nothing")
    func skipMoved() throws {
        let (scene, list) = try movedGym()
        list.confirmSkip(try overdueRow(list).row)
        list.confirm()
        #expect(scene.recorded.isEmpty)
        let item = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(item.occurrence(on: key)?.outcome == .skipped)
    }

    @Test("Edit opens the form on the 18 Oct occurrence, with its own amount and due day")
    func editMoved() throws {
        let (scene, list) = try movedGym()
        #expect(list.tableCommand(.edit, selection: try overdueRow(list).id))
        let form = try #require(list.form)
        #expect(form.occurrence == key)
        #expect(form.dueDay == CalendarDay(year: 2026, month: 10, day: 19))
        #expect(form.amountText.contains("1300") || form.amountText.contains("1,300"))
        // The scene owns the store the list reads; keep it to the end.
        withExtendedLifetime(scene) {}
    }
}

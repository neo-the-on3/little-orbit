import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// S33: the item Debug › Tap Scheduled Reminder opens when the launch argument names none.
@Suite("Default reminder item (S33)")
@MainActor
struct ScheduledDefaultReminderItemTests {
    @Test("No items: nothing to tap")
    func none() throws {
        let scene = try ScheduledScene()
        #expect(scene.feature().defaultReminderItemID() == nil)
    }

    @Test("No item notifies when due: the first item in the list's order, overdue first")
    func firstItem() throws {
        let scene = try ScheduledScene()
        let upcoming = scene.item("Phone Plan", day: 5, month: 11)
        let overdue = scene.item("Rent", day: 1, month: 10)
        try scene.add(upcoming, overdue)
        #expect(scene.feature().defaultReminderItemID() == overdue.id)
    }

    @Test("The first item with Notify when due on wins over an earlier one without it")
    func notifying() throws {
        let scene = try ScheduledScene()
        var upcoming = scene.item("Phone Plan", day: 5, month: 11)
        upcoming.notifiesWhenDue = true
        let overdue = scene.item("Rent", day: 1, month: 10)
        try scene.add(overdue, upcoming)
        #expect(scene.feature().defaultReminderItemID() == upcoming.id)
    }
}

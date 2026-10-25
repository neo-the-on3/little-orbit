import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// D338.6: the catch-up hint stays pending across a relaunch until the Scheduled screen has shown it.
@MainActor
@Suite("Pending catch-up notice in app settings", .timeLimit(.minutes(2)))
struct UserDefaultsScheduledCatchUpNoticesTests {
    private static let rent = UUID()
    private static let salary = UUID()

    private func defaults() throws -> (UserDefaults, String) {
        let name = "scheduled-notice-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    private func catchUp(_ groups: [UUID: [CalendarDay]], order: [UUID]) -> ScheduledCatchUp {
        let posted = order.flatMap { id in
            (groups[id] ?? [])
                .map { day in
                    Transaction(
                        type: .expense,
                        amount: 1,
                        date: Self.noon(day),
                        timeZoneID: Self.zone,
                        accountID: UUID(),
                        scheduledTemplateID: id,
                        scheduledOccurrenceDate: Self.noon(day),
                        createdAt: Self.noon(day),
                    )
                }
        }
        return ScheduledCatchUp(posted: posted)
    }

    private static let zone = "Asia/Kolkata"

    private static func noon(_ day: CalendarDay) -> Date {
        TransactionCalendar.noon(on: day, timeZoneID: zone) ?? .distantPast
    }

    private static func day(_ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: month, day: day)
    }

    @Test("Unseen, it's kept across a relaunch, and a later catch-up merges in per item")
    func keptAndMerged() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let first = ScheduledCatchUpNotices(store: UserDefaultsScheduledCatchUpNotices(defaults: defaults))
        first.add(catchUp([Self.rent: [Self.day(8, 1), Self.day(9, 1)]], order: [Self.rent]))

        let relaunched = ScheduledCatchUpNotices(store: UserDefaultsScheduledCatchUpNotices(defaults: defaults))
        #expect(
            relaunched.pending() == [
                ScheduledCatchUpGroup(itemID: Self.rent, days: [Self.day(8, 1), Self.day(9, 1)])
            ]
        )
        relaunched.add(
            catchUp(
                [Self.salary: [Self.day(10, 1)], Self.rent: [Self.day(9, 1), Self.day(10, 1)]],
                order: [Self.salary, Self.rent],
            )
        )
        #expect(
            relaunched.pending() == [
                ScheduledCatchUpGroup(itemID: Self.rent, days: [Self.day(8, 1), Self.day(9, 1), Self.day(10, 1)]),
                ScheduledCatchUpGroup(itemID: Self.salary, days: [Self.day(10, 1)]),
            ]
        )
        // Leaving Scheduled before it was shown keeps it.
        relaunched.dismissIfShown()
        #expect(relaunched.pending().count == 2)
    }

    @Test("Shown, it goes when Scheduled is left, or at the next launch if the app quit first")
    func clearedOnceShown() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let notices = ScheduledCatchUpNotices(store: UserDefaultsScheduledCatchUpNotices(defaults: defaults))
        notices.add(catchUp([Self.rent: [Self.day(8, 1)]], order: [Self.rent]))
        notices.markShown()
        notices.dismissIfShown()
        #expect(notices.pending().isEmpty)
        #expect(defaults.data(forKey: UserDefaultsScheduledCatchUpNotices.key) == nil)

        notices.add(catchUp([Self.rent: [Self.day(9, 1)]], order: [Self.rent]))
        notices.markShown()
        #expect(
            ScheduledCatchUpNotices(store: UserDefaultsScheduledCatchUpNotices(defaults: defaults)).pending().isEmpty
        )
    }

    @Test("It keeps item IDs and days only, and an unreadable value is dropped")
    func idsAndDaysOnly() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UserDefaultsScheduledCatchUpNotices(defaults: defaults)
        store.setNotice(
            ScheduledCatchUpNotice(groups: [ScheduledCatchUpGroup(itemID: Self.rent, days: [Self.day(8, 1)])])
        )
        let data = try #require(defaults.data(forKey: UserDefaultsScheduledCatchUpNotices.key))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["groups", "shown"])
        let group = try #require((json["groups"] as? [[String: Any]])?.first)
        #expect(Set(group.keys) == ["itemID", "days"])
        defaults.set(Data("not json".utf8), forKey: UserDefaultsScheduledCatchUpNotices.key)
        #expect(store.notice() == nil)
    }
}

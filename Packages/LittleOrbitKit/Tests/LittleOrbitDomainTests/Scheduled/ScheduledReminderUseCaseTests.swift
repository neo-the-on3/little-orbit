import Foundation
import LittleOrbitDomain
import Testing

/// A fake of the system's notifications behind `ScheduledNotificationScheduling`, in place of the App's
/// `UNUserNotificationCenter` adapter: what's pending, by identifier, and every add and removal it was asked for.
@MainActor
final class FakeNotificationScheduling: ScheduledNotificationScheduling {
    var current: NotificationPermission
    var answer: NotificationPermission
    private(set) var pending: [String: ScheduledNotificationRequest] = [:]
    /// Pending requests that aren't reminders, which a reschedule leaves alone.
    var others: Set<String> = []
    private(set) var prompts = 0
    /// Each `add` call's identifiers, in order.
    private(set) var added: [[String]] = []
    /// Each `removePending` call's identifiers, in order.
    private(set) var removed: [[String]] = []
    /// The zone the device is in, which a calendar trigger with no zone of its own fires in (S23).
    var deviceZone = TimeZone(identifier: ScheduledFixture.zone)!

    init(_ permission: NotificationPermission = .allowed, answer: NotificationPermission = .allowed) {
        current = permission
        self.answer = answer
    }

    /// When a pending request fires: its day at its time, in `deviceZone`, as the adapter's calendar trigger does.
    func fireDate(_ request: ScheduledNotificationRequest) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = deviceZone
        return calendar.date(
            from: DateComponents(
                year: request.day.year,
                month: request.day.month,
                day: request.day.day,
                hour: request.time.hour,
                minute: request.time.minute,
            )
        )
    }

    /// Every pending reminder's fire date, earliest first.
    var fireDates: [Date] {
        pending.values.compactMap(fireDate).sorted()
    }

    func permission() async -> NotificationPermission {
        current
    }

    func requestPermission() async -> NotificationPermission {
        if current == .notDetermined {
            prompts += 1
            current = answer
        }
        return current
    }

    func pendingIdentifiers() async -> [String] {
        Array(pending.keys) + others
    }

    func add(_ requests: [ScheduledNotificationRequest]) async throws {
        added.append(requests.map(\.id))
        for request in requests {
            pending[request.id] = request
        }
    }

    func removePending(_ identifiers: [String]) {
        removed.append(identifiers)
        for identifier in identifiers {
            pending[identifier] = nil
            others.remove(identifier)
        }
    }

    var days: [CalendarDay] {
        pending.values.map(\.day).sorted()
    }
}

/// Words reminders with the item's description, so the tests can see the text reach the request.
struct EchoReminderWording: ScheduledReminderWording {
    func content(for reminder: ScheduledReminder, in listing: ScheduledListing) -> ScheduledNotificationContent {
        let account = listing.account(reminder.item.accountID)?.name ?? ""
        return ScheduledNotificationContent(
            title: reminder.item.details ?? "",
            body: "\(reminder.kind == .automatic ? "auto" : "manual") \(account)",
        )
    }
}

@MainActor
@Suite("Scheduled reminder use cases (#26, D340.7)")
struct ScheduledReminderUseCaseTests {
    private typealias Fix = ScheduledFixture

    private let repository = FakeScheduleRepository()
    private let notifications = FakeNotificationScheduling()
    private let times = InMemoryScheduledReminderTimeStore()

    private var reminders: DefaultScheduledReminderUseCases {
        DefaultScheduledReminderUseCases(
            repository: repository,
            notifications: notifications,
            times: times,
            wording: EchoReminderWording(),
            now: { [repository] in repository.now },
            timeZone: { TimeZone(identifier: Fix.zone)! },
        )
    }

    private func electricity(day: Int = 20, automatic: Bool = false) throws -> ScheduledItem {
        var item = Fix.rent(start: Fix.day(2026, 8, day), end: Fix.day(2026, 12, 31), automatic: automatic)
        item.details = "Electricity"
        item.notifiesWhenDue = true
        repository.now = Fix.created
        try repository.useCases().save(item)
        repository.now = Fix.date(2026, 10, 20, 8)
        return item
    }

    @Test("Schedules each occurrence still ahead, worded, with the item's ID")
    func schedules() async throws {
        let item = try electricity()
        try await reminders.reschedule()
        #expect(notifications.days == [Fix.day(2026, 10, 20), Fix.day(2026, 11, 20), Fix.day(2026, 12, 20)])
        let request = try #require(notifications.pending.values.first { $0.day == Fix.day(2026, 10, 20) })
        #expect(request.itemID == item.id)
        #expect(request.time == .standard)
        #expect(request.content == ScheduledNotificationContent(title: "Electricity", body: "manual Everyday Savings"))
        #expect(request.id == ScheduledReminder.identifier(item: item.id, day: Fix.day(2026, 10, 20)))
    }

    @Test("Paying today's occurrence removes its reminder; the later ones stay")
    func payDropsIt() async throws {
        let item = try electricity()
        try await reminders.reschedule()
        try repository.useCases().payNow(itemID: item.id, occurrence: Fix.day(2026, 10, 20))
        try await reminders.reschedule()
        #expect(notifications.days == [Fix.day(2026, 11, 20), Fix.day(2026, 12, 20)])
    }

    @Test("Deleting the item, or its account, removes every reminder")
    func deleteDropsAll() async throws {
        let item = try electricity()
        try await reminders.reschedule()
        try repository.useCases().delete(id: item.id)
        try await reminders.reschedule()
        #expect(notifications.pending.isEmpty)

        let other = try electricity(day: 25)
        try await reminders.reschedule()
        #expect(!notifications.pending.isEmpty)
        repository.snapshot.accounts.removeAll { $0.id == other.accountID }
        try await reminders.reschedule()
        #expect(notifications.pending.isEmpty)
    }

    @Test("S10: a new Reminder Time reschedules the same identifiers at it")
    func reminderTimeChange() async throws {
        _ = try electricity()
        try await reminders.reschedule()
        let identifiers = Set(notifications.pending.keys)
        reminders.setReminderTime(ReminderTime(hour: 18, minute: 30))
        #expect(reminders.reminderTime() == ReminderTime(hour: 18, minute: 30))
        try await reminders.reschedule()
        #expect(Set(notifications.pending.keys) == identifiers)
        #expect(notifications.pending.values.allSatisfy { $0.time == ReminderTime(hour: 18, minute: 30) })
    }

    @Test("Notifications that aren't reminders are left alone")
    func othersLeftAlone() async throws {
        _ = try electricity()
        notifications.others = ["backup.done"]
        try await reminders.reschedule()
        #expect(notifications.others == ["backup.done"])
    }

    @Test("Without permission nothing is scheduled and pending reminders go")
    func denied() async throws {
        _ = try electricity()
        try await reminders.reschedule()
        #expect(!notifications.pending.isEmpty)
        notifications.current = .denied
        try await reminders.reschedule()
        #expect(notifications.pending.isEmpty)
    }

    @Test("The permission prompt is the system's, shown only while not yet asked")
    func permissionPrompt() async {
        let fresh = FakeNotificationScheduling(.notDetermined, answer: .denied)
        let useCases = DefaultScheduledReminderUseCases(
            repository: repository,
            notifications: fresh,
            times: times,
            wording: EchoReminderWording(),
            now: { Date() },
            timeZone: { .current },
        )
        #expect(await useCases.permission() == .notDetermined)
        #expect(await useCases.requestPermission() == .denied)
        #expect(await useCases.requestPermission() == .denied)
        #expect(fresh.prompts == 1)
    }

    @Test("S11: an automatic item recorded at catch-up still gets its one reminder that day")
    func automaticAfterCatchUp() async throws {
        _ = try electricity(automatic: true)
        _ = try repository.useCases().catchUp(atLaunch: true)
        try await reminders.reschedule()
        let today = try #require(notifications.pending.values.first { $0.day == Fix.day(2026, 10, 20) })
        #expect(today.content.body == "auto Everyday Savings")
        #expect(notifications.days.filter { $0 == Fix.day(2026, 10, 20) }.count == 1)
    }
}

import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Counts reschedules, for the triggers: launch, activation, every change and a Reminder Time change (D340.7).
@MainActor
final class CountingReminderUseCase: ScheduleRemindersUseCase {
    private(set) var count = 0
    /// Thrown by each reschedule while set.
    var failure: (any Error)?
    /// Runs during the next reschedule, as a change made while one runs would.
    var during: (() -> Void)?

    func reschedule() async throws {
        count += 1
        let during = during
        self.during = nil
        during?()
        if let failure {
            throw failure
        }
    }
}

/// Answers the permission prompt the way a test says, counting prompts.
@MainActor
final class PromptingPermission: NotificationPermissionUseCase {
    var current: NotificationPermission
    let answer: NotificationPermission
    private(set) var prompts = 0

    init(_ current: NotificationPermission, answer: NotificationPermission) {
        self.current = current
        self.answer = answer
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
}

@MainActor
@Suite("Scheduled reminders: form, Settings and wording (#26, D340.7, D341)")
struct ScheduledReminderTests {
    private static let british = Locale(identifier: "en_GB")

    private func list(
        _ scene: ScheduledScene,
        permission: any NotificationPermissionUseCase,
        time: ReminderTime = .standard,
        platform: ScheduledPlatform = .iOS,
    )
        -> ScheduledListViewModel
    {
        var useCases = scene.useCases
        useCases.permission = permission
        useCases.reminderTime = FixedReminderTime(time)
        let list = ScheduledListViewModel(useCases: useCases, locale: Self.british, platform: platform)
        list.load()
        return list
    }

    @Test("The form's Notify when due is saved on the item, and its footnote names the Reminder Time")
    func toggleSaved() async throws {
        let scene = try ScheduledScene()
        let list = list(
            scene,
            permission: FixedNotificationPermission(.allowed),
            time: ReminderTime(hour: 18, minute: 30),
        )
        list.openNew()
        let form = try #require(list.form)
        #expect(form.notifyLabel == "Notify when due")
        #expect(!form.notifiesWhenDue)
        #expect(
            form.footnote
                == "Automatic items are recorded on the due date, or when you next open the app. "
                + "Reminders arrive at 18:30 (Settings › Scheduled Items)."
        )
        form.amountText = "1850"
        form.notifiesWhenDue = true
        await form.permissionCheck?.value
        #expect(!form.showsOpenSettings)
        #expect(form.save())
        let saved = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(saved.notifiesWhenDue)
    }

    @Test(
        "D341.3: the first turn-on shows the system prompt; denied keeps the toggle on with the footer and Open Settings"
    )
    func deniedPrompt() async throws {
        let scene = try ScheduledScene()
        let permission = PromptingPermission(.notDetermined, answer: .denied)
        let list = list(scene, permission: permission)
        list.openNew()
        let form = try #require(list.form)
        form.notifiesWhenDue = true
        await form.permissionCheck?.value
        #expect(permission.prompts == 1)
        #expect(form.notifiesWhenDue)
        #expect(form.showsOpenSettings)
        #expect(form.openSettingsTitle == "Open Settings")
        let nine = ReminderTimeText.string(.standard, locale: Self.british)
        #expect(form.footnote.hasSuffix("Reminders arrive at \(nine) (Settings › Scheduled Items)."))
        #expect(
            form.notificationsOffFootnote
                == "Notifications are off for little-orbit, so reminders can’t arrive. Turn them on in Settings."
        )
        // Turning it off and on again doesn't prompt a second time.
        form.notifiesWhenDue = false
        #expect(!form.showsOpenSettings)
        form.notifiesWhenDue = true
        await form.permissionCheck?.value
        #expect(permission.prompts == 1)
        #expect(form.showsOpenSettings)
    }

    @Test("D360.3: the Mac toggle names the Reminder Time, and its footer leaves the time sentence out; iOS unchanged")
    func macToggleNamesTime() throws {
        let scene = try ScheduledScene()
        let time = ReminderTime(hour: 18, minute: 30)
        let mac = list(scene, permission: FixedNotificationPermission(.allowed), time: time, platform: .macOS)
        mac.openNew()
        let macForm = try #require(mac.form)
        #expect(macForm.notifyLabel == "Notify when due (18:30)")
        #expect(macForm.footnote == "Automatic items are recorded on the due date, or when you next open the app.")
        let iOS = list(scene, permission: FixedNotificationPermission(.allowed), time: time, platform: .iOS)
        iOS.openNew()
        let iOSForm = try #require(iOS.form)
        #expect(iOSForm.notifyLabel == "Notify when due")
        #expect(iOSForm.footnote.hasSuffix("Reminders arrive at 18:30 (Settings › Scheduled Items)."))
    }

    @Test("D359: denied on the Mac, the row and its footer name System Settings; iOS says Settings")
    func deniedWordingByPlatform() async throws {
        let scene = try ScheduledScene()
        let mac = list(scene, permission: PromptingPermission(.notDetermined, answer: .denied), platform: .macOS)
        mac.openNew()
        let macForm = try #require(mac.form)
        macForm.notifiesWhenDue = true
        await macForm.permissionCheck?.value
        #expect(macForm.notifiesWhenDue)
        #expect(macForm.showsOpenSettings)
        #expect(macForm.openSettingsTitle == "Open System Settings")
        #expect(
            macForm.notificationsOffFootnote
                == "Notifications are off for little-orbit, so reminders can’t arrive. Turn them on in System Settings."
        )
        let iOS = list(scene, permission: PromptingPermission(.notDetermined, answer: .denied), platform: .iOS)
        iOS.openNew()
        let iOSForm = try #require(iOS.form)
        iOSForm.notifiesWhenDue = true
        await iOSForm.permissionCheck?.value
        #expect(iOSForm.openSettingsTitle == "Open Settings")
        #expect(iOSForm.notificationsOffFootnote.hasSuffix("Turn them on in Settings."))
    }

    @Test("Opening a notified item while notifications are denied shows the footer without prompting")
    func deniedOnOpen() async throws {
        let scene = try ScheduledScene()
        var item = scene.item("Electricity", day: 15)
        item.notifiesWhenDue = true
        try scene.add(item)
        let permission = PromptingPermission(.denied, answer: .denied)
        let list = list(scene, permission: permission)
        list.openEditor(item.id)
        let form = try #require(list.form)
        await form.permissionCheck?.value
        #expect(form.notifiesWhenDue)
        #expect(form.showsOpenSettings)
        #expect(permission.prompts == 0)
        permission.current = .allowed
        form.refreshNotificationPermission()
        await form.permissionCheck?.value
        #expect(!form.showsOpenSettings)
    }

    @Test("D341.4: Settings › Scheduled Items › Reminder Time is 09:00 until changed, and a change reschedules")
    func settings() async throws {
        let scene = try ScheduledScene()
        let counter = CountingReminderUseCase()
        let reminders = ScheduledReminders(useCase: counter)
        var useCases = scene.useCases
        let time = FixedReminderTime()
        useCases.reminderTime = time
        let feature = ScheduledFeature(useCases: useCases, updates: scene.updates, reminders: reminders)
        let settings = feature.makeReminderSettings()
        #expect(settings.time == .standard)
        #expect(settings.sectionTitle == "Scheduled Items")
        #expect(settings.rowTitle == "Reminder Time")
        #expect(settings.footer == "Scheduled items set to “Notify when due” remind you at this time.")
        settings.setTime(ReminderTime(hour: 18, minute: 30))
        await reminders.inFlight?.value
        #expect(time.reminderTime() == ReminderTime(hour: 18, minute: 30))
        #expect(counter.count == 1)
        // The same time again changes nothing.
        settings.setTime(ReminderTime(hour: 18, minute: 30))
        #expect(reminders.inFlight == nil)
        #expect(counter.count == 1)
    }

    @Test("The time picker's date round-trips the Reminder Time in the device's zone")
    func pickerDate() {
        let zone = TimeZone(identifier: "Europe/London")!
        let settings = ScheduledReminderSettingsViewModel(useCase: FixedReminderTime(), timeZone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(calendar.component(.hour, from: settings.date) == 9)
        settings.date = calendar.date(bySettingHour: 7, minute: 45, second: 0, of: settings.date)!
        #expect(settings.time == ReminderTime(hour: 7, minute: 45))
        #expect(ReminderTimeText.string(settings.time, locale: Self.british).hasSuffix("7:45"))
    }

    @Test("Catch-up at launch and on activation, and every change, reschedule the reminders")
    func triggers() async throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Electricity", day: 15))
        let counter = CountingReminderUseCase()
        let reminders = ScheduledReminders(useCase: counter)
        let feature = ScheduledFeature(useCases: scene.useCases, updates: scene.updates, reminders: reminders)
        feature.catchUp(atLaunch: true)
        await reminders.inFlight?.value
        let afterLaunch = counter.count
        #expect(afterLaunch >= 1)
        let list = feature.makeList()
        list.load()
        list.payNow(try #require(list.overdueRows.first))
        await reminders.inFlight?.value
        #expect(counter.count > afterLaunch)
        let afterPay = counter.count
        scene.updates.ledgerReplaced()
        await reminders.inFlight?.value
        #expect(counter.count > afterPay)
    }

    @Test("Refreshes asked for before a run starts are one run; ones asked for during it make one more")
    func coalesced() async {
        let counter = CountingReminderUseCase()
        let reminders = ScheduledReminders(useCase: counter)
        let first = reminders.refresh()
        reminders.refresh()
        await first.value
        #expect(counter.count == 1)
        counter.during = {
            reminders.refresh()
            reminders.refresh()
        }
        await reminders.refresh().value
        #expect(counter.count == 3)
        #expect(reminders.inFlight == nil)
    }

    @Test("A refused reschedule is passed on once per launch for each error code (Tech Architect NB2)")
    func problemOncePerCode() async {
        let counter = CountingReminderUseCase()
        var problems: [Int] = []
        let reminders = ScheduledReminders(useCase: counter) { problems.append(($0 as NSError).code) }
        counter.failure = NSError(domain: "UNErrorDomain", code: 1)
        await reminders.refresh().value
        await reminders.refresh().value
        counter.failure = NSError(domain: "UNErrorDomain", code: 2)
        await reminders.refresh().value
        await reminders.refresh().value
        counter.failure = NSError(domain: "UNErrorDomain", code: 1)
        await reminders.refresh().value
        #expect(counter.count == 5)
        #expect(problems == [1, 2])
    }

    @Test("D340.7: the reminder names the item; its body has no amount, account or category")
    func wording() throws {
        let scene = try ScheduledScene()
        let composer = ScheduledReminderComposer(locale: Self.british, platform: .iOS)
        let listing = try scene.useCases.load.listing()
        let manual = scene.item("Electricity", day: 15)
        var rent = scene.item("Rent", day: 1, automatic: true)
        rent.notifiesWhenDue = true
        let day = CalendarDay(year: 2026, month: 11, day: 15)
        let manualContent = composer.content(
            for: ScheduledReminder(item: manual, day: day, time: .standard, fireDate: Date()),
            in: listing,
        )
        #expect(
            manualContent
                == ScheduledNotificationContent(title: "Electricity is due today", body: "Tap to pay or skip.")
        )
        let rentContent = composer.content(
            for: ScheduledReminder(item: rent, day: day, time: .standard, fireDate: Date()),
            in: listing,
        )
        #expect(rentContent.title == "Rent is due today")
        #expect(rentContent.body == "It’s recorded automatically, once.")
        for text in [manualContent.body, rentContent.body] {
            #expect(!text.contains("1,200") && !text.contains("Everyday Savings") && !text.contains("Housing"))
        }
    }

    @Test("D354.3: a manual reminder says Click on the Mac and Tap on iOS; an automatic one is the same on both")
    func platformWording() throws {
        let scene = try ScheduledScene()
        let listing = try scene.useCases.load.listing()
        let day = CalendarDay(year: 2026, month: 11, day: 15)
        let manual = ScheduledReminder(
            item: scene.item("Electricity", day: 15),
            day: day,
            time: .standard,
            fireDate: Date(),
        )
        var rent = scene.item("Rent", day: 1, automatic: true)
        rent.notifiesWhenDue = true
        let automatic = ScheduledReminder(item: rent, day: day, time: .standard, fireDate: Date())
        let mac = ScheduledReminderComposer(locale: Self.british, platform: .macOS)
        let iOS = ScheduledReminderComposer(locale: Self.british, platform: .iOS)
        #expect(mac.content(for: manual, in: listing).body == "Click to pay or skip.")
        #expect(iOS.content(for: manual, in: listing).body == "Tap to pay or skip.")
        #expect(mac.content(for: manual, in: listing).title == "Electricity is due today")
        #expect(mac.content(for: automatic, in: listing).body == iOS.content(for: automatic, in: listing).body)
    }
}

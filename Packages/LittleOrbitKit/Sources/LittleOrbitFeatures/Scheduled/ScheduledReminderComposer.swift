import Foundation
import LittleOrbitDomain

/// Words each reminder (D340.7, privacy version): the title names the item, “Electricity is due today”, and the
/// body never shows an amount, account or category, so nothing private is on the Lock Screen (S32). A manual item's
/// body says Tap on iOS and Click on the Mac (D354.3).
@MainActor
public struct ScheduledReminderComposer: ScheduledReminderWording {
    private let locale: Locale
    private let platform: ScheduledPlatform

    public init(locale: Locale = .current, platform: ScheduledPlatform = .current) {
        self.locale = locale
        self.platform = platform
    }

    public func content(for reminder: ScheduledReminder, in listing: ScheduledListing) -> ScheduledNotificationContent {
        let name = ScheduledPresenter(listing: listing, locale: locale).shortName(of: reminder.item)
        let body =
            switch reminder.kind {
            case .manual: ScheduledText.manualReminderBody(platform)
            case .automatic: ScheduledText.automaticReminderBody
            }
        return ScheduledNotificationContent(title: ScheduledText.dueTodayTitle(name), body: body)
    }
}

/// The Reminder Time as the device writes times: “09:00”, or “9:00 AM” (D341.4).
enum ReminderTimeText {
    static func string(_ time: ReminderTime, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = ScheduledPresenter.utc
        return date(time, in: ScheduledPresenter.utc).formatted(style)
    }

    /// `time` on a fixed day in `zone`, for a time picker, which shows and sets it in that zone.
    static func date(_ time: ReminderTime, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(
            from: DateComponents(year: 2001, month: 1, day: 1, hour: time.hour, minute: time.minute)
        ) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    static func time(of date: Date, in zone: TimeZone) -> ReminderTime {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return ReminderTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
    }
}

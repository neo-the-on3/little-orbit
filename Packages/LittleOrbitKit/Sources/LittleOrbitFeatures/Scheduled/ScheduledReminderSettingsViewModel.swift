import Foundation
import LittleOrbitDomain
import Observation

/// Settings › Scheduled Items › Reminder Time (D341.4): one time for every item's reminders, 09:00 by default.
/// Changing it reschedules every pending reminder at the new time (S10).
@MainActor
@Observable
public final class ScheduledReminderSettingsViewModel {
    public private(set) var time: ReminderTime

    @ObservationIgnored private let useCase: any ScheduledReminderTimeUseCase
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let changed: () -> Void

    /// `timeZone` is the one the time picker shows its date in, the device's.
    public init(
        useCase: any ScheduledReminderTimeUseCase,
        timeZone: TimeZone = .autoupdatingCurrent,
        changed: @escaping () -> Void = {},
    ) {
        self.useCase = useCase
        self.timeZone = timeZone
        self.changed = changed
        time = useCase.reminderTime()
    }

    public var sectionTitle: String { ScheduledText.settingsSection }
    public var rowTitle: String { ScheduledText.reminderTime }
    public var footer: String { ScheduledText.reminderTimeFooter }

    /// What the `.hourAndMinute` picker shows and sets.
    public var date: Date {
        get { ReminderTimeText.date(time, in: timeZone) }
        set { setTime(ReminderTimeText.time(of: newValue, in: timeZone)) }
    }

    public func setTime(_ newTime: ReminderTime) {
        guard newTime != time else {
            return
        }
        time = newTime
        useCase.setReminderTime(newTime)
        changed()
    }
}

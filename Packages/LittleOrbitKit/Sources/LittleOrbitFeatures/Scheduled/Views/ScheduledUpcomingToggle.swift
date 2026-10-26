#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// "Show upcoming" (D348, UI Designer): the first row of the Scheduled Items section, before Reminder Time
    /// (`ScheduledReminderSettingsSection` on iOS, `ScheduledReminderSettingsTab` on the Mac).
    struct ScheduledUpcomingToggle: View {
        @Bindable var model: ScheduledUpcomingSettingsModel

        var body: some View {
            Toggle(model.toggleTitle, isOn: $model.showsUpcoming)
        }
    }
#endif

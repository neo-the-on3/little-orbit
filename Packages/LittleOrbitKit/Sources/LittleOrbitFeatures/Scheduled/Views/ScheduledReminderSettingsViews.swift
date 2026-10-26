#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// Settings › Scheduled Items (D341.4, D348; #197 frame "Settings › Notifications – Reminder Time"): the Show
    /// upcoming switch, then one `.hourAndMinute` Reminder Time row, 09:00 by default, in the device's time format,
    /// and its footer, in one section. iOS puts it in the Settings list; the Mac in its own Settings tab,
    /// `ScheduledReminderSettingsTab`.
    public struct ScheduledReminderSettingsSection: View {
        @State private var model: ScheduledReminderSettingsViewModel
        private let upcoming: ScheduledUpcomingSettingsModel?

        public init(feature: ScheduledFeature, upcoming: ScheduledUpcomingSettingsModel? = nil) {
            _model = State(initialValue: feature.makeReminderSettings())
            self.upcoming = upcoming
        }

        public var body: some View {
            ScheduledItemsSettingsSection(model: model, upcoming: upcoming)
        }
    }

    /// The Mac Settings window's Scheduled Items tab: the same section in a grouped Form, with system defaults.
    public struct ScheduledReminderSettingsTab: View {
        @State private var model: ScheduledReminderSettingsViewModel
        private let upcoming: ScheduledUpcomingSettingsModel?

        public init(feature: ScheduledFeature, upcoming: ScheduledUpcomingSettingsModel? = nil) {
            _model = State(initialValue: feature.makeReminderSettings())
            self.upcoming = upcoming
        }

        /// The tab's title, "Scheduled Items".
        public static var title: String { ScheduledText.settingsSection }

        public var body: some View {
            Form {
                ScheduledItemsSettingsSection(model: model, upcoming: upcoming)
            }
            .formStyle(.grouped)
        }
    }

    private struct ScheduledItemsSettingsSection: View {
        @Bindable var model: ScheduledReminderSettingsViewModel
        let upcoming: ScheduledUpcomingSettingsModel?

        var body: some View {
            Section {
                if let upcoming {
                    ScheduledUpcomingToggle(model: upcoming)
                }
                DatePicker(model.rowTitle, selection: $model.date, displayedComponents: .hourAndMinute)
            } header: {
                Text(model.sectionTitle)
            } footer: {
                Text(model.footer)
            }
        }
    }
#endif

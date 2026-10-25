#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// Settings › Scheduled Items (D341.4; #197 frame "Settings › Notifications – Reminder Time"): one
    /// `.hourAndMinute` Reminder Time row, 09:00 by default, in the device's time format, and its footer. iOS puts it
    /// in the Settings list; the Mac in its own Settings tab, `ScheduledReminderSettingsTab`.
    public struct ScheduledReminderSettingsSection: View {
        @State private var model: ScheduledReminderSettingsViewModel

        public init(feature: ScheduledFeature) {
            _model = State(initialValue: feature.makeReminderSettings())
        }

        public var body: some View {
            ScheduledReminderTimeSection(model: model)
        }
    }

    /// The Mac Settings window's Scheduled Items tab: the same section in a grouped Form, with system defaults.
    public struct ScheduledReminderSettingsTab: View {
        @State private var model: ScheduledReminderSettingsViewModel

        public init(feature: ScheduledFeature) {
            _model = State(initialValue: feature.makeReminderSettings())
        }

        /// The tab's title, "Scheduled Items".
        public static var title: String { ScheduledText.settingsSection }

        public var body: some View {
            Form {
                ScheduledReminderTimeSection(model: model)
            }
            .formStyle(.grouped)
        }
    }

    private struct ScheduledReminderTimeSection: View {
        @Bindable var model: ScheduledReminderSettingsViewModel

        var body: some View {
            Section {
                DatePicker(model.rowTitle, selection: $model.date, displayedComponents: .hourAndMinute)
            } header: {
                Text(model.sectionTitle)
            } footer: {
                Text(model.footer)
            }
        }
    }
#endif

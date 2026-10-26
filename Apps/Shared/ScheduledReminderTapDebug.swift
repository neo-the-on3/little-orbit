// Debug-only S33 testing hooks for a tapped scheduled reminder: the launch argument's tap and Debug › Tap
// Scheduled Reminder. None of it is in release builds or on the watch.
#if (os(iOS) || os(macOS)) && DEBUG
    import Foundation
    import LittleOrbitFeatures
    import SwiftUI

    @MainActor
    extension AppComposition {
        /// S33 testing hooks, Debug builds only; nothing is logged. `-LittleOrbitScheduledReminderTap <item ID>`
        /// taps that item's reminder, which the simulator can't, through the same handler once launch is done,
        /// or `-LittleOrbitScheduledReminderTapAfter <seconds>` later, so a sheet can be opened and edited first.
        /// `-LittleOrbitScheduledReminderSecondTap <item ID>` with `-LittleOrbitScheduledReminderSecondTapAfter
        /// <seconds>` adds a second tap with its own delay from launch, for two taps in a row.
        /// The returned closure is Debug › Tap Scheduled Reminder's warm tap, through the same handler: the item
        /// the argument names, else the first one with Notify when due on, else the first one.
        static func debugReminderTaps(
            for feature: ScheduledFeature,
            through notifications: UserNotificationScheduling,
        ) -> () -> Void {
            let arguments = ProcessInfo.processInfo.arguments
            // The first tap and, with -LittleOrbitScheduledReminderSecondTap, a second, each after its own delay.
            for tap in ScheduledReminderTapLaunch.take(arguments: arguments) {
                Task { @MainActor in
                    if let delay = tap.delay {
                        try? await Task.sleep(for: delay)
                    }
                    notifications.openItemFromLaunchArgument(tap.itemID)
                }
            }
            return {
                guard
                    let itemID = ScheduledReminderTapLaunch.itemID(in: arguments) ?? feature.defaultReminderItemID()
                else {
                    return
                }
                notifications.openItemFromLaunchArgument(itemID)
            }
        }
    }

    /// Debug › Tap Scheduled Reminder (S33), on the Mac and in the iPad menu bar: a warm tap on a scheduled
    /// item's reminder, which Tester can't click on demand, through the same handler as
    /// `-LittleOrbitScheduledReminderTap`. On the Mac, like a real tap, it unhides the app after Cmd-H, brings
    /// back a minimised window, or opens a new one when every window is closed. Debug builds only; the titles
    /// are fixed English, not catalog entries.
    struct ScheduledReminderTapCommand: Commands {
        let features: Result<AppFeatures, any Error>

        var body: some Commands {
            CommandMenu(Text(verbatim: "Debug")) {
                Button {
                    if case .success(let features) = features {
                        features.tapScheduledReminder()
                    }
                } label: {
                    Text(verbatim: "Tap Scheduled Reminder")
                }
            }
        }
    }
#endif

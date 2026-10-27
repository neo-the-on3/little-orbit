import LittleOrbitFeatures
import SwiftUI

@main
struct LittleOrbitMacApp: App {
    /// Built once per launch by the composition root, here rather than in a view, then passed down.
    private let features: Result<AppFeatures, any Error>

    /// File > Restore from Backup… opens Settings > Backups with its file panel.
    @State private var isPickingBackupFile = false

    init() {
        features = AppComposition.make()
    }

    var body: some Scene {
        // The main windows. A tapped reminder opens a new one by this ID when none is open (S33).
        WindowGroup(id: UserNotificationScheduling.mainWindowID) {
            RootView(features: features)
        }
        .commands {
            // Off while a Bulk Edit, or its Undo or Redo, runs in any window (D399).
            RestoreFromBackupCommand(
                isPickingFile: $isPickingBackupFile,
                ledgerUpdates: (try? features.get())?.transactions.updates,
            )
            ImportExportCommands()
            #if DEBUG
                ScheduledReminderTapCommand(features: features)
            #endif
        }

        // The standard Settings window, opened with Cmd-, from the app menu (D179.5). It's the shared home for
        // app settings: Scheduled Items, with Show upcoming (D348) and Reminder Time (#26, D341.4), then Backups
        // (#40). Later tabs (Security with App Lock, #29) go before Backups.
        Settings {
            if case .success(let features) = features {
                TabView {
                    Tab(ScheduledReminderSettingsTab.title, systemImage: "calendar.badge.clock") {
                        ScheduledReminderSettingsTab(feature: features.scheduled, upcoming: features.scheduledUpcoming)
                    }
                    Tab("Backups", systemImage: "clock.arrow.circlepath") {
                        BackupsSettingsTab(
                            model: features.backups,
                            ledgerUpdates: features.transactions.updates,
                            isPickingFile: $isPickingBackupFile,
                        )
                    }
                }
            }
        }
    }
}

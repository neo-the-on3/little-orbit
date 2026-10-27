import LittleOrbitFeatures
import SwiftUI

/// The Mac app's entry point. It makes the app's `NSApplication` a `LittleOrbitApplication` before SwiftUI starts,
/// so each Undo or Redo can tell the event it was dispatched with from an Accessibility action (B5 on #286).
///
/// AppKit's documented way to use a subclass is to send `shared` to it first: `shared` creates the app object only
/// once, and every later `NSApplication.shared` returns that one. `NSPrincipalClass` only works through
/// `NSApplicationMain`, and SwiftUI's `App.main()` didn't honour it (Tester2 on 4ea9bd6: the subclass was named in the
/// built Info.plist and in the binary, but `NSApp` was a plain `NSApplication`). At launch the signpost
/// `ledger.command.dispatchSource` reads `live`; `absent` is logged as a fault and stops a Debug build.
@main
enum LittleOrbitMacMain {
    @MainActor
    static func main() {
        LittleOrbitApplication.makeShared()
        LittleOrbitMacApp.main()
    }
}

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

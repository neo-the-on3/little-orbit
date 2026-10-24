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
        WindowGroup {
            RootView(features: features)
        }
        // A defined first size, so the history table's Payee column fits a refund title (D235.1).
        .defaultSize(width: 1200, height: 760)
        .commands {
            RestoreFromBackupCommand(isPickingFile: $isPickingBackupFile)
            // Edit > Refund… (⌘R) for the selected expense (#34).
            TransactionCommands()
        }

        // The standard Settings window, opened with Cmd-, from the app menu (D179.5). It's the shared home for
        // app settings and holds only the Backups tab (#40) for now; later tabs (Security with App Lock, #29)
        // go before it.
        Settings {
            if case .success(let features) = features {
                TabView {
                    Tab("Backups", systemImage: "clock.arrow.circlepath") {
                        BackupsSettingsTab(model: features.backups, isPickingFile: $isPickingBackupFile)
                    }
                }
            }
        }
    }
}

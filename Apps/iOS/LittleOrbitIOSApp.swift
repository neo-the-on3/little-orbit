import LittleOrbitFeatures
import SwiftUI
import UIKit

@main
struct LittleOrbitIOSApp: App {
    /// Built once per launch by the composition root, here rather than in a view, then passed down.
    private let features: Result<AppFeatures, any Error>
    private let backgroundActivity = UIKitBackgroundActivity()

    init() {
        features = AppComposition.make()
    }

    var body: some Scene {
        WindowGroup {
            RootView(features: features, backgroundActivity: backgroundActivity)
        }
        #if DEBUG
            // The iPad menu bar's Debug › Tap Scheduled Reminder, as on the Mac (S33). iPhone has no menu bar.
            .commands { ScheduledReminderTapCommand(features: features) }
        #endif
    }
}

/// Background time for the backup when the app goes to the background, from UIKit. It's the only UIKit piece;
/// Domain and Features see `BackgroundActivity`. `ProcessInfo.performExpiringActivity` would need the backup to run
/// synchronously on its thread, and the backup is async work on the main actor.
@MainActor
final class UIKitBackgroundActivity: BackgroundActivity {
    func begin(_ name: String, expired: @escaping @MainActor () -> Void) -> BackgroundActivityID? {
        let id = UIApplication.shared.beginBackgroundTask(withName: name) {
            // UIKit calls this on the main thread.
            MainActor.assumeIsolated { expired() }
        }
        return id == .invalid ? nil : BackgroundActivityID(rawValue: id.rawValue)
    }

    func end(_ id: BackgroundActivityID) {
        UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: id.rawValue))
    }
}

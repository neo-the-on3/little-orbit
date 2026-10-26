import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import SwiftUI

@main
struct LittleOrbitWatchApp: App {
    /// Built once per launch by the composition root, then passed down.
    private let scheduled: WatchScheduledViewModel

    init() {
        scheduled = WatchComposition.makeScheduled()
    }

    var body: some Scene {
        WindowGroup {
            WatchScheduledListView(model: scheduled)
        }
    }
}

/// The watch's composition root (#197 item 10). No ledger and no App Group (D345): the Scheduled list reads the
/// iPhone's snapshot over WatchConnectivity, with a disposable cache in the watch app's own settings.
@MainActor
enum WatchComposition {
    static func makeScheduled() -> WatchScheduledViewModel {
        let timeZone: @MainActor () -> TimeZone = { TimeZone.autoupdatingCurrent }
        var now: @MainActor () -> Date = { Date() }
        #if DEBUG
            // D337.2: the same `-LittleOrbitScheduledToday 2026-10-20` as the iPhone, so a watch Pay is dated on the
            // day the test sets. Not in release builds.
            if let day = ScheduledDebugClock.overriddenDay(in: ProcessInfo.processInfo.arguments) {
                now = ScheduledDebugClock.clock(today: day, launchedAt: Date(), timeZone: timeZone, now: { Date() })
            }
        #endif
        let clock = now
        let useCases = DefaultWatchScheduledUseCases(
            link: WatchPhoneSession(),
            cache: UserDefaultsWatchScheduledCache(),
            today: { TransactionTiming.today(clock(), timeZone: timeZone()) },
        )
        return WatchScheduledViewModel(useCases: useCases)
    }
}

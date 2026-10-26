import Foundation
import LittleOrbitDomain
import Observation

/// Settings › Scheduled Items › "Show upcoming" (D348): an On/Off switch, On by default. Turning it off takes the
/// scheduled Upcoming rows out of every account history, and every window's histories reload.
@MainActor
@Observable
public final class ScheduledUpcomingSettingsModel {
    @ObservationIgnored private let store: any ShowUpcomingSettingStore
    @ObservationIgnored private let updates: LedgerUpdates?
    @ObservationIgnored private var replacedHandler: LedgerUpdates.ReplacedHandler?

    public var showsUpcoming: Bool {
        didSet {
            guard showsUpcoming != store.showsUpcoming else {
                return
            }
            store.showsUpcoming = showsUpcoming
            updates?.changed()
        }
    }

    public init(store: any ShowUpcomingSettingStore, updates: LedgerUpdates? = nil) {
        self.store = store
        self.updates = updates
        showsUpcoming = store.showsUpcoming
        // A restore puts the backup's value back in the store (D348); the switch shows it.
        replacedHandler = updates?
            .onLedgerReplaced { [weak self] in
                guard let self else {
                    return
                }
                showsUpcoming = store.showsUpcoming
            }
    }

    /// The Settings section and the Mac Settings tab: "Scheduled Items" (UI Designer, D348).
    public var sectionTitle: String { ScheduledText.settingsSection }

    public var toggleTitle: String { ScheduledText.showUpcoming }
}

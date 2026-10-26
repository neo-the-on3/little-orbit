import Foundation
import LittleOrbitDomain

/// The watch's disposable cache (D345): the last snapshot from the iPhone and the Pay and Skip requests still
/// syncing or turned down, in the watch app's own settings. No ledger and no App Group: losing it loses nothing,
/// since the iPhone sends a new snapshot and the system still delivers queued requests.
@MainActor
public final class UserDefaultsWatchScheduledCache: WatchScheduledCache {
    static let snapshotKey = "watch.scheduled.snapshot"
    static let sentKey = "watch.scheduled.sent"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func snapshotData() -> Data? {
        defaults.data(forKey: Self.snapshotKey)
    }

    public func setSnapshotData(_ data: Data?) {
        defaults.set(data, forKey: Self.snapshotKey)
    }

    /// An unreadable list is dropped: the requests were already handed to the system to deliver.
    public func sentRequests() -> [WatchSentRequest] {
        defaults.data(forKey: Self.sentKey).flatMap { try? JSONDecoder().decode([WatchSentRequest].self, from: $0) }
            ?? []
    }

    public func setSentRequests(_ requests: [WatchSentRequest]) {
        guard !requests.isEmpty, let data = try? JSONEncoder().encode(requests) else {
            defaults.removeObject(forKey: Self.sentKey)
            return
        }
        defaults.set(data, forKey: Self.sentKey)
    }
}

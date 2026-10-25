import Foundation
import LittleOrbitDomain

/// The pending catch-up notice in this device's app settings (D338.6), so the hint survives a relaunch until the
/// Scheduled screen has shown it. It keeps item IDs, days and whether it was shown: never names or amounts. It isn't
/// ledger data, so no backup holds it and the store's schema doesn't change.
@MainActor
public final class UserDefaultsScheduledCatchUpNotices: ScheduledCatchUpNoticeStore {
    static let key = "scheduled.catchUp.pendingNotice"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nil` when nothing is kept, or what's kept can't be read: an unreadable notice is dropped, never shown.
    public func notice() -> ScheduledCatchUpNotice? {
        guard let data = defaults.data(forKey: Self.key) else {
            return nil
        }
        return try? JSONDecoder().decode(ScheduledCatchUpNotice.self, from: data)
    }

    public func setNotice(_ notice: ScheduledCatchUpNotice?) {
        guard let notice, let data = try? JSONEncoder().encode(notice) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}

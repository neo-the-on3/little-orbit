import Foundation
import LittleOrbitDomain

/// "Show upcoming" in app settings (D348). It's read as D348 rules: Off stays Off, any other stored value (an older
/// Next month, Next quarter or Next year range) is On, and no stored value is On. Saving it writes a plain Bool.
@MainActor
public final class UserDefaultsShowUpcomingSetting: ShowUpcomingSettingStore {
    static let key = "scheduled.showUpcoming"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var showsUpcoming: Bool {
        get {
            switch defaults.object(forKey: Self.key) {
            case let value as Bool: value
            case let value as String: value.lowercased() != "off"
            default: true
            }
        }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

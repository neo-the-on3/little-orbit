import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// D348: Show upcoming in app settings. Nothing stored is On, a stored Off stays Off, and an older range (Next
/// month, quarter or year) is On.
@MainActor
@Suite("Show upcoming in app settings (D348)")
struct UserDefaultsShowUpcomingSettingTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "show-upcoming-\(UUID().uuidString)"))
    }

    @Test("Nothing stored is On; a saved Off is read back after a relaunch")
    func defaultAndSaved() throws {
        let defaults = try defaults()
        let setting = UserDefaultsShowUpcomingSetting(defaults: defaults)
        #expect(setting.showsUpcoming)
        setting.showsUpcoming = false
        #expect(!UserDefaultsShowUpcomingSetting(defaults: defaults).showsUpcoming)
    }

    @Test(
        "A stored Off stays Off; an older Next month, quarter or year is On",
        arguments: [
            ("off", false), ("Off", false), ("nextMonth", true), ("nextQuarter", true), ("nextYear", true),
        ],
    )
    func olderValues(stored: String, isOn: Bool) throws {
        let defaults = try defaults()
        defaults.set(stored, forKey: UserDefaultsShowUpcomingSetting.key)
        #expect(UserDefaultsShowUpcomingSetting(defaults: defaults).showsUpcoming == isOn)
    }
}

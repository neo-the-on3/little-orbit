import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// D374, D376: the notices for watch requests the iPhone didn't apply stay in app settings across a relaunch until
/// they're dismissed, IDs only.
@MainActor
@Suite("Watch request notices in app settings", .timeLimit(.minutes(2)))
struct UserDefaultsWatchRequestInboxTests {
    @Test("Pending notices survive a relaunch, and a dismissed one stays gone")
    func survivesRelaunch() throws {
        let name = "watch-inbox-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let pay = WatchRequestNotice(id: UUID(), reason: .itemChanged, action: .pay, itemID: UUID())
        let newer = WatchRequestNotice(id: UUID(), reason: .newerWatchApp, action: nil, itemID: nil)
        UserDefaultsWatchRequestInbox(defaults: defaults).setNotices([pay, newer])

        let relaunched = UserDefaultsWatchRequestInbox(defaults: defaults)
        #expect(relaunched.notices() == [pay, newer])
        relaunched.setNotices([newer])
        #expect(UserDefaultsWatchRequestInbox(defaults: defaults).notices() == [newer])
        relaunched.setNotices([])
        #expect(defaults.data(forKey: UserDefaultsWatchRequestInbox.noticesKey) == nil)
        #expect(UserDefaultsWatchRequestInbox(defaults: defaults).notices().isEmpty)
    }
}

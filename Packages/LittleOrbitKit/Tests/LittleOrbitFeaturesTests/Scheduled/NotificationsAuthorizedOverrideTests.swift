#if DEBUG
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitFeatures
    import Testing

    /// The DEBUG-only `-LittleOrbitNotificationsAuthorized YES` override at the notification adapter.
    @MainActor
    @Suite("Notifications authorized override (#204, DEBUG)")
    struct NotificationsAuthorizedOverrideTests {
        /// A system center that was never asked, counting prompts and keeping what's pending.
        @MainActor
        private final class NeverAskedCenter: ScheduledNotificationScheduling {
            private(set) var prompts = 0
            private(set) var pending: [String] = []

            func permission() async -> NotificationPermission { .notDetermined }

            func requestPermission() async -> NotificationPermission {
                prompts += 1
                return .denied
            }

            func pendingIdentifiers() async -> [String] { pending }

            func add(_ requests: [ScheduledNotificationRequest]) async throws {
                pending += requests.map(\.id)
            }

            func removePending(_ identifiers: [String]) {
                pending.removeAll { identifiers.contains($0) }
            }
        }

        private func request(_ id: String) -> ScheduledNotificationRequest {
            ScheduledNotificationRequest(
                id: id,
                itemID: UUID(),
                day: CalendarDay(year: 2026, month: 10, day: 26),
                time: .standard,
                content: ScheduledNotificationContent(title: "Title", body: "Body"),
            )
        }

        @Test("The argument is on only when followed by YES")
        func parsing() {
            let argument = NotificationsAuthorizedOverride.argument
            #expect(argument == "-LittleOrbitNotificationsAuthorized")
            #expect(NotificationsAuthorizedOverride.isOn(in: ["app", argument, "YES"]))
            #expect(NotificationsAuthorizedOverride.isOn(in: ["app", argument, "true"]))
            #expect(!NotificationsAuthorizedOverride.isOn(in: ["app"]))
            #expect(!NotificationsAuthorizedOverride.isOn(in: ["app", argument]))
            #expect(!NotificationsAuthorizedOverride.isOn(in: ["app", argument, "NO"]))
        }

        @Test("With the argument, permission reads allowed with no prompt, and requests still reach the center")
        func authorized() async throws {
            let center = NeverAskedCenter()
            let notifications = NotificationsAuthorizedOverride.applying(
                to: center,
                arguments: ["app", NotificationsAuthorizedOverride.argument, "YES"],
            )
            #expect(await notifications.permission() == .allowed)
            #expect(await notifications.requestPermission() == .allowed)
            #expect(center.prompts == 0)
            try await notifications.add([request("a"), request("b")])
            #expect(center.pending == ["a", "b"])
            #expect(await notifications.pendingIdentifiers() == ["a", "b"])
            notifications.removePending(["a"])
            #expect(center.pending == ["b"])
        }

        @Test("Without the argument, the center is used as it is")
        func unchanged() async {
            let center = NeverAskedCenter()
            let notifications = NotificationsAuthorizedOverride.applying(to: center, arguments: ["app"])
            #expect(notifications === center)
            #expect(await notifications.permission() == .notDetermined)
            #expect(await notifications.requestPermission() == .denied)
            #expect(center.prompts == 1)
        }
    }
#endif

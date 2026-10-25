#if DEBUG
    import Foundation
    import LittleOrbitDomain

    /// DEBUG builds only: a launch argument that treats notification permission as granted, so Tester can check
    /// 'Notify when due' reminders on a simulator or the Mac VM without the system prompt (Tester's and Tester2's
    /// #204 passes at 38050b0, check 5 BLOCKED). It isn't compiled into release builds. The App wraps its
    /// notification adapter with it; the system center still adds and removes every request as usual.
    ///
    /// `-LittleOrbitNotificationsAuthorized YES`.
    public enum NotificationsAuthorizedOverride {
        public static let argument = "-LittleOrbitNotificationsAuthorized"

        /// Whether `arguments` hold `argument` followed by YES (or true or 1, as the argument domain reads them).
        public static func isOn(in arguments: [String]) -> Bool {
            guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else {
                return false
            }
            return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
        }

        /// `notifications`, wrapped so permission reads as allowed when `arguments` turn the override on.
        @MainActor
        public static func applying(
            to notifications: any ScheduledNotificationScheduling,
            arguments: [String],
        ) -> any ScheduledNotificationScheduling {
            isOn(in: arguments) ? AuthorizedNotificationScheduling(notifications) : notifications
        }
    }

    /// The App's notification adapter with permission always allowed and never asked for. Pending requests, adds
    /// and removals go to the wrapped adapter unchanged.
    @MainActor
    public final class AuthorizedNotificationScheduling: ScheduledNotificationScheduling {
        private let wrapped: any ScheduledNotificationScheduling

        public init(_ wrapped: any ScheduledNotificationScheduling) {
            self.wrapped = wrapped
        }

        public func permission() async -> NotificationPermission {
            .allowed
        }

        /// No system prompt: the override already counts as the answer.
        public func requestPermission() async -> NotificationPermission {
            .allowed
        }

        public func pendingIdentifiers() async -> [String] {
            await wrapped.pendingIdentifiers()
        }

        public func add(_ requests: [ScheduledNotificationRequest]) async throws {
            try await wrapped.add(requests)
        }

        public func removePending(_ identifiers: [String]) {
            wrapped.removePending(identifiers)
        }
    }
#endif

#if os(iOS) || os(macOS)
    import Foundation
    import LittleOrbitDomain
    import UserNotifications

    /// The system's local notifications for scheduled items' reminders (#26, D340.7), the only `UserNotifications`
    /// piece: Domain and Features see `ScheduledNotificationScheduling`. Each request is a calendar trigger on the
    /// due day at the Reminder Time with no time zone, so it arrives at that wall-clock time wherever the device is
    /// (S23). Local notifications need no entitlement. It's also the center's delegate, so a reminder that arrives
    /// while the app is open still shows (the Mac app is often open at 09:00).
    @MainActor
    final class UserNotificationScheduling: NSObject, ScheduledNotificationScheduling {
        /// The item a reminder is about, by ID only, for opening it from the notification later.
        static let itemIDKey = "scheduledItemID"

        private let center: UNUserNotificationCenter
        /// Called when a reminder arrives while the app is open, so the pending budget refills: the composition root
        /// reschedules. One that arrives while the app isn't running is refilled at the next launch or activation.
        var onReminderDelivered: (() -> Void)?

        override init() {
            center = UNUserNotificationCenter.current()
            super.init()
            center.delegate = self
        }

        func permission() async -> NotificationPermission {
            await withCheckedContinuation { continuation in
                center.getNotificationSettings { settings in
                    continuation.resume(returning: Self.permission(settings.authorizationStatus))
                }
            }
        }

        func requestPermission() async -> NotificationPermission {
            let current = await permission()
            guard current == .notDetermined else {
                return current
            }
            let _: Bool = await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            return await permission()
        }

        func pendingIdentifiers() async -> [String] {
            await withCheckedContinuation { continuation in
                center.getPendingNotificationRequests { requests in
                    continuation.resume(returning: requests.map(\.identifier))
                }
            }
        }

        /// Adds every request, carrying on past one the system refuses (Tech Architect NB2). The first failure is
        /// thrown once all have been tried, so the caller logs it once, with no user data.
        func add(_ requests: [ScheduledNotificationRequest]) async throws {
            var firstFailure: (any Error)?
            for request in requests {
                let content = UNMutableNotificationContent()
                content.title = request.content.title
                content.body = request.content.body
                content.sound = .default
                content.threadIdentifier = "scheduled"
                content.userInfo = [Self.itemIDKey: request.itemID.uuidString]
                let when = DateComponents(
                    year: request.day.year,
                    month: request.day.month,
                    day: request.day.day,
                    hour: request.time.hour,
                    minute: request.time.minute,
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
                let system = UNNotificationRequest(identifier: request.id, content: content, trigger: trigger)
                do {
                    try await add(system)
                } catch {
                    firstFailure = firstFailure ?? error
                }
            }
            if let firstFailure {
                throw firstFailure
            }
        }

        private func add(_ request: UNNotificationRequest) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                center.add(request) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }

        func removePending(_ identifiers: [String]) {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        private nonisolated static func permission(_ status: UNAuthorizationStatus) -> NotificationPermission {
            switch status {
            case .notDetermined: .notDetermined
            case .denied: .denied
            default: .allowed
            }
        }
    }

    extension UserNotificationScheduling: UNUserNotificationCenterDelegate {
        /// A reminder that arrives while the app is in front still shows as a banner, and refills the budget.
        nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
        ) async -> UNNotificationPresentationOptions {
            if notification.request.identifier.hasPrefix(ScheduledReminder.identifierPrefix) {
                await MainActor.run {
                    onReminderDelivered?()
                }
            }
            return [.banner, .list, .sound]
        }
    }
#endif

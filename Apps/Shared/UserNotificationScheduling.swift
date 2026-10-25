#if os(iOS) || os(macOS)
    import Foundation
    import LittleOrbitDomain
    import UserNotifications

    #if os(macOS)
        import AppKit
        import LittleOrbitFeatures
    #endif

    /// The system's local notifications for scheduled items' reminders (#26, D340.7), the only `UserNotifications`
    /// piece: Domain and Features see `ScheduledNotificationScheduling`. Each request is a calendar trigger on the
    /// due day at the Reminder Time with no time zone, so it arrives at that wall-clock time wherever the device is
    /// (S23). Local notifications need no entitlement. It's also the center's delegate, so a reminder that arrives
    /// while the app is open still shows (the Mac app is often open at 09:00).
    @MainActor
    final class UserNotificationScheduling: NSObject, ScheduledNotificationScheduling {
        /// The item a reminder is about, by ID only, for opening it from the notification later.
        nonisolated static let itemIDKey = "scheduledItemID"

        private let center: UNUserNotificationCenter
        /// Called when a reminder arrives while the app is open, so the pending budget refills: the composition root
        /// reschedules. One that arrives while the app isn't running is refilled at the next launch or activation.
        var onReminderDelivered: (() -> Void)?
        /// Opens the item a tapped reminder is about (S33), with the identifier of the scene the system sent the
        /// tap to on iOS (`nil` on the Mac). Set once by the composition root; a tap that arrives before then waits
        /// in `waitingTap`.
        var onOpenItem: ((UUID, String?) -> Void)? {
            didSet {
                if let onOpenItem, let waitingTap {
                    self.waitingTap = nil
                    onOpenItem(waitingTap.itemID, waitingTap.scene)
                }
            }
        }
        private var waitingTap: (itemID: UUID, scene: String?)?

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
        /// S33: tapping a reminder opens its item. The ID is the only thing read from the notification, with, on
        /// iOS, the scene the system sent the response to (Tech Architect NB2). The Mac picks its main window in
        /// `bringMainWindowForward(among:)`. Dismissing it, or another app's notification, does nothing.
        nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
        ) async {
            guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
                response.notification.request.identifier.hasPrefix(ScheduledReminder.identifierPrefix),
                let text = response.notification.request.content.userInfo[Self.itemIDKey] as? String,
                let itemID = UUID(uuidString: text)
            else {
                return
            }
            #if os(iOS)
                // Only the reference is taken here. UIScene is main-actor bound, so it's Sendable, and its
                // session is read on the main actor below.
                let targetScene = response.targetScene
            #endif
            await MainActor.run {
                #if os(iOS)
                    openItem(itemID, scene: targetScene?.session.persistentIdentifier)
                #else
                    openItem(itemID, scene: nil)
                #endif
            }
        }

        private func openItem(_ itemID: UUID, scene: String?) {
            if let onOpenItem {
                onOpenItem(itemID, scene)
            } else {
                waitingTap = (itemID, scene)
            }
        }

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

    #if os(macOS)
        extension UserNotificationScheduling {
            /// The main window group's ID, for `openWindow(id:)`.
            static let mainWindowID = "main"

            /// Opens a new main window. A main window sets it from its `openWindow` action, so it still works once
            /// every main window has closed.
            static var openMainWindow: (() -> Void)?

            /// Brings a main window to the front for a tapped reminder (UI Designer 6402418696, Tech Architect NB2),
            /// unhiding the app first after Cmd-H: the key one, else the frontmost, else a minimised one, which comes
            /// back. With none open it opens a new one and returns `nil`, so that window takes the tap once it's up.
            /// `windows` are the main windows' numbers; Settings isn't one, so it stays where it is, behind.
            static func bringMainWindowForward(among windows: [String]) -> String? {
                let app = NSApplication.shared
                // After Cmd-H every window is hidden, so none would count as key, frontmost or minimised and a
                // second window would open (#219 item 1). Unhiding first brings the app's windows back as they were.
                if app.isHidden {
                    app.unhide(nil)
                }
                let ordered = app.orderedWindows
                let mains = app.windows.filter { windows.contains(String($0.windowNumber)) }
                let candidates = mains.map { window in
                    ScheduledReminderRouting.MacWindow(
                        id: String(window.windowNumber),
                        isKey: window.isKeyWindow,
                        isMiniaturized: window.isMiniaturized,
                        order: window.isVisible && !window.isMiniaturized ? ordered.firstIndex(of: window) : nil,
                    )
                }
                app.activate()
                guard let chosen = ScheduledReminderRouting.macWindow(candidates),
                    let window = mains.first(where: { String($0.windowNumber) == chosen.id })
                else {
                    openMainWindow?()
                    return nil
                }
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
                return chosen.id
            }
        }
    #endif
#endif

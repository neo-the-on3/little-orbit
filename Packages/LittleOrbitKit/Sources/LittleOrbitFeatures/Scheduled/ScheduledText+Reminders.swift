import Foundation

/// The wording of 'Notify when due' (#26, D340.7, D341.3, D341.4): the form's toggle and footnotes, Settings ›
/// Scheduled Items, and the reminders themselves.
extension ScheduledText {
    // MARK: Form

    static var notifyWhenDue: String {
        FeatureText.string(
            "Notify when due",
            comment: "Scheduled form toggle: send a local notification on each occurrence’s due day (D341).",
        )
    }

    /// The Mac's toggle, "Notify when due (09:00)", with the current Reminder Time (D360.3).
    static func notifyWhenDue(at time: String) -> String {
        FeatureText.format("Notify when due (%@)", time)
    }

    /// "Reminders arrive at 09:00 (Settings › Scheduled Items)." with the current Reminder Time (D340.7).
    static func remindersArrive(at time: String) -> String {
        FeatureText.format("Reminders arrive at %@ (Settings › Scheduled Items).", time)
    }

    /// The footer under Open Settings when Notify when due is on but notifications are denied (D341.3, D359).
    static func notificationsOff(_ platform: ScheduledPlatform) -> String {
        switch platform {
        case .iOS:
            FeatureText.string(
                "Notifications are off for little-orbit, so reminders can’t arrive. Turn them on in Settings.",
                comment: "iOS Scheduled form footer under Open Settings, when notifications are denied (D341.3).",
            )
        case .macOS:
            FeatureText.string(
                "Notifications are off for little-orbit, so reminders can’t arrive. Turn them on in System Settings.",
                comment: "Mac Scheduled form footer under Open System Settings, when notifications are denied (D359).",
            )
        }
    }

    /// The row that opens the app's notification settings (D341.3, D359).
    static func openSettings(_ platform: ScheduledPlatform) -> String {
        switch platform {
        case .iOS:
            FeatureText.string(
                "Open Settings",
                comment: "iOS Scheduled form row above the notifications-off footer: opens notification settings.",
            )
        case .macOS:
            FeatureText.string(
                "Open System Settings",
                comment: "Mac Scheduled form row above the notifications-off footer: opens System Settings.",
            )
        }
    }

    // MARK: Settings

    static var settingsSection: String {
        FeatureText.string(
            "Scheduled Items",
            comment: "Settings section, and the Mac Settings tab, for scheduled items’ reminders (D341.4).",
        )
    }

    static var reminderTime: String {
        FeatureText.string(
            "Reminder Time",
            comment: "Settings › Scheduled Items: the time picker for when reminders arrive (D341.4).",
        )
    }

    static var reminderTimeFooter: String {
        FeatureText.string(
            "Scheduled items set to “Notify when due” remind you at this time.",
            comment: "Settings › Scheduled Items footer under Reminder Time (D341.4).",
        )
    }

    // MARK: Notification (D340.7, privacy version)

    /// "Electricity is due today".
    static func dueTodayTitle(_ name: String) -> String {
        FeatureText.format("%@ is due today", name)
    }

    /// "Tap to pay or skip." on iOS, "Click to pay or skip." on the Mac (D354.3).
    static func manualReminderBody(_ platform: ScheduledPlatform) -> String {
        switch platform {
        case .iOS:
            FeatureText.string(
                "Tap to pay or skip.",
                comment: "iOS reminder body for a manual scheduled item, with no amount, account or category (D340.7).",
            )
        case .macOS:
            FeatureText.string(
                "Click to pay or skip.",
                comment: "Mac reminder body for a manual scheduled item, with no amount, account or category (D354.3).",
            )
        }
    }

    static var automaticReminderBody: String {
        FeatureText.string(
            "It’s recorded automatically, once.",
            comment: "Reminder body for an automatic scheduled item, with no amount, account or category (D340.7).",
        )
    }
}

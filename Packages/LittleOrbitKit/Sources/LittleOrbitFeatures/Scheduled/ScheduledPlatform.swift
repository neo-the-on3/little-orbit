import Foundation

/// The platform the wording follows: iOS rows are links, so its hint says how to reach Pay and Skip; Mac menus
/// take an ellipsis on items that ask first (D334.1, D334.10).
public enum ScheduledPlatform: Sendable {
    case iOS
    case macOS

    public static var current: ScheduledPlatform {
        #if os(macOS)
            .macOS
        #else
            .iOS
        #endif
    }
}

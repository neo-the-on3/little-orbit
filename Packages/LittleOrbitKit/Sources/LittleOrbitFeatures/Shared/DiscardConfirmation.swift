import Foundation

/// The system discard prompt for an edit sheet (D300.1): Cancel, or a swipe down, with unsaved edits asks
/// “Discard Changes?” with Discard Changes and Keep Editing, and no message; with none, the sheet just closes.
/// The sheet applies it with `confirmsDiscardingChanges(isDirty:confirmation:onDiscard:)` on iOS.
public struct DiscardConfirmation: Equatable, Sendable {
    /// Whether “Discard Changes?” is on show.
    public var isPresented = false

    public init() {}

    /// Cancel or a swipe down. With unsaved edits it asks first and returns false; otherwise it returns true,
    /// and the sheet closes.
    public mutating func requestDismiss(isDirty: Bool) -> Bool {
        if isDirty {
            isPresented = true
            return false
        }
        return true
    }
}

/// The discard prompt's wording (D300.1), for every edit sheet.
enum DiscardText {
    static var title: String {
        FeatureText.string(
            "Discard Changes?",
            comment: "Edit sheet confirmation title: Cancel or a swipe down with unsaved edits. It has no message.",
        )
    }

    static var discard: String {
        FeatureText.string(
            "Discard Changes",
            comment: "Discard confirmations (D300): closes the sheet with nothing saved.",
        )
    }

    static var keepEditing: String {
        FeatureText.string(
            "Keep Editing",
            comment: "Discard confirmations (D300): goes back to the sheet with the edits intact.",
        )
    }
}

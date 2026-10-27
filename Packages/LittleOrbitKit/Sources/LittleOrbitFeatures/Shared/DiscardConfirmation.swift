import Foundation

/// The system discard prompt for an edit sheet (D300.1): Cancel, or a swipe down, with unsaved edits asks
/// “Discard Changes?” with Discard Changes and Keep Editing; with none, the sheet just closes. It has no message
/// unless the sheet gives one, as the Scheduled form's Edit sheet does (D388.1). On iOS the sheet applies it with
/// `confirmsDiscardingChanges(isDirty:confirmation:message:onDiscard:)` and puts
/// `discardsChangesFromCancel(confirmation:message:onDiscard:)` on its Cancel button. Each has its own dialog, so
/// the one from Cancel points at Cancel and the one from a swipe shows at the top centre. A Mac sheet has only
/// the Cancel button's.
public struct DiscardConfirmation: Equatable, Sendable {
    /// What asked to close the sheet.
    public enum Source: Equatable, Sendable {
        case cancel
        case swipe
    }

    /// What “Discard Changes?” is on show for, if it's on show.
    public private(set) var source: Source?

    public init() {}

    /// Whether “Discard Changes?” is on show.
    public var isPresented: Bool {
        source != nil
    }

    /// The Cancel button's dialog. Closing it clears the prompt.
    public var isPresentedFromCancel: Bool {
        get { source == .cancel }
        set { set(.cancel, newValue) }
    }

    /// The swipe-down dialog. Closing it clears the prompt.
    public var isPresentedFromSwipe: Bool {
        get { source == .swipe }
        set { set(.swipe, newValue) }
    }

    /// Cancel or a swipe down. With unsaved edits it asks first, from `source`, and returns false; otherwise it
    /// returns true, and the sheet closes.
    public mutating func requestDismiss(isDirty: Bool, from source: Source) -> Bool {
        if isDirty {
            self.source = source
            return false
        }
        return true
    }

    private mutating func set(_ source: Source, _ isPresented: Bool) {
        if isPresented {
            self.source = source
        } else if self.source == source {
            self.source = nil
        }
    }
}

/// The discard prompt's wording (D300.1), for every edit sheet.
enum DiscardText {
    static var title: String {
        FeatureText.string(
            "Discard Changes?",
            comment: "Edit sheet confirmation title: Cancel, Esc on the Mac or a swipe down with unsaved edits.",
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

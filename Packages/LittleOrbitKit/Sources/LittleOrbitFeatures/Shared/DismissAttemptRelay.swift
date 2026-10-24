import Foundation

/// Passes a refused swipe down on an edit sheet to its discard prompt (D300.1), with the sheet's unsaved-edits
/// state as it is when the swipe happens, not when the bridge was installed. The iOS bridge updates `isDirty`
/// on every view update and calls `attempt()` from the sheet's presentation delegate.
@MainActor
final class DismissAttemptRelay {
    var isDirty: Bool
    var request: (_ isDirty: Bool) -> Void

    init(isDirty: Bool = false, request: @escaping (_ isDirty: Bool) -> Void = { _ in }) {
        self.isDirty = isDirty
        self.request = request
    }

    func attempt() {
        request(isDirty)
    }
}

/// What installing the swipe bridge does with the sheet's current presentation delegate. SwiftUI can set its own
/// delegate again after ours, for example when `interactiveDismissDisabled` changes, so the bridge installs
/// again on later updates and layouts, and must never wrap its own proxy or another bridge's.
enum DismissAttemptInstall: Equatable {
    /// Our proxy is already the delegate.
    case keep
    /// Another bridge's proxy is the delegate: point it at our relay instead of wrapping it.
    case adopt
    /// Anything else, or no delegate: wrap it in a new proxy that passes everything on to it.
    case wrap

    static func step(delegateIsOurProxy: Bool, delegateIsProxy: Bool) -> Self {
        if delegateIsOurProxy {
            return .keep
        }
        return delegateIsProxy ? .adopt : .wrap
    }
}

import Foundation

/// Passes a refused swipe down on an edit sheet to its discard prompt (D300.1), with the sheet's unsaved-edits
/// state as it is when the swipe happens, not when the bridge was installed. The iOS bridge updates `isDirty`
/// on every view update; the sheet's presentation delegate asks `shouldDismiss(original:)` and calls `attempt()`.
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

    /// Whether a swipe down may close the sheet (presentationControllerShouldDismiss). While there are unsaved
    /// edits, read now, it refuses, so UIKit reports the refused swipe and the prompt shows, even if
    /// `interactiveDismissDisabled` hasn't made the sheet modal yet (#167). Otherwise it's the original delegate's
    /// answer, or true when it has none; the original isn't asked while there are unsaved edits.
    func shouldDismiss(original: (() -> Bool)?) -> Bool {
        if isDirty {
            return false
        }
        return original?() ?? true
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

extension DismissAttemptInstall {
    /// The sheet's presented root: `start` or the nearest of its ancestors that was itself presented. The bridge
    /// installs on that controller's presentation controller, because asking any other controller for one
    /// (UIKit's `presentationController`) can make a new, unused presentation controller for it, which UIKit
    /// never calls. Nil while the bridge isn't in a presented sheet yet, so it tries again later.
    static func presentedRoot<Node: AnyObject>(
        from start: Node?,
        parent: (Node) -> Node?,
        isPresented: (Node) -> Bool,
    ) -> Node? {
        var node = start
        while let current = node {
            if isPresented(current) {
                return current
            }
            node = parent(current)
        }
        return nil
    }
}

/// The presented sheet as the swipe bridge sees it: only its presentation delegate. The bridge never reads or
/// writes whether the sheet is modal (`isModalInPresentation`): SwiftUI's `interactiveDismissDisabled` is its
/// only writer, so a re-install can't put back a stale value and let an edited sheet close (#167).
@MainActor
protocol DismissAttemptSheet {
    associatedtype Proxy: AnyObject

    /// The sheet's presentation delegate, if it's a bridge proxy (ours or another bridge's).
    var delegateProxy: Proxy? { get }

    /// Points a bridge proxy that's already the delegate at `relay`.
    func adopt(_ proxy: Proxy, relay: DismissAttemptRelay)

    /// Makes a proxy around the current delegate, sets it as the delegate, and returns it.
    func wrapDelegate(relay: DismissAttemptRelay) -> Proxy
}

/// Installs the swipe bridge's proxy on a sheet, as many times as the bridge is asked to: it keeps its own
/// proxy, adopts another bridge's, and wraps anything else, and touches nothing but the delegate.
@MainActor
final class DismissAttemptInstaller<Sheet: DismissAttemptSheet> {
    let relay: DismissAttemptRelay
    private(set) var proxy: Sheet.Proxy?

    init(relay: DismissAttemptRelay) {
        self.relay = relay
    }

    /// Returns what it did, so the bridge can log a new install.
    @discardableResult
    func install(on sheet: Sheet) -> DismissAttemptInstall {
        let current = sheet.delegateProxy
        let step = DismissAttemptInstall.step(
            delegateIsOurProxy: proxy != nil && current === proxy,
            delegateIsProxy: current != nil,
        )
        switch step {
        case .keep:
            break
        case .adopt:
            if let current {
                sheet.adopt(current, relay: relay)
                proxy = current
            }
        case .wrap:
            proxy = sheet.wrapDelegate(relay: relay)
        }
        return step
    }
}

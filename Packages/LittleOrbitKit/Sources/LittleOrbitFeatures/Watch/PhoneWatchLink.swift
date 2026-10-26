import Foundation
import LittleOrbitDomain

/// What the iPhone's session says about the paired watch.
public struct WatchSessionState: Equatable, Sendable {
    public var isPaired: Bool
    public var isWatchAppInstalled: Bool

    public init(isPaired: Bool, isWatchAppInstalled: Bool) {
        self.isPaired = isPaired
        self.isWatchAppInstalled = isWatchAppInstalled
    }

    /// A watch is paired and has the app, so a context can reach it.
    public var canReceive: Bool { isPaired && isWatchAppInstalled }
}

/// The parts of the iPhone's WatchConnectivity session the link uses. The App's adapter wraps `WCSession`; tests
/// use a fake that, like `WCSession`, drops a context identical to the one it has.
@MainActor
public protocol WatchContextSession: AnyObject {
    var watchState: WatchSessionState { get }
    func updateApplicationContext(_ context: [String: Any]) throws
}

/// The iPhone end of the watch link (#48, #197 item 10), over a `WatchContextSession`. The App's adapter forwards
/// the session's events here, so the delivery rules are tested without WatchConnectivity.
///
/// - Nothing counts as delivered before activation completes: a pre-activation install flag can be stale, so a
///   publish before then waits (Tester F1).
/// - Every publish carries a new stamp beside the snapshot, so a deliberate re-send is never byte-identical and the
///   session never drops it as "no change". The feature still skips a snapshot the watch already has.
/// - Activation with the watch app installed, and every `sessionWatchStateDidChange` while the watch can receive,
///   ask the feature to send the current snapshot again, once per callback: a removal and a reinstall can arrive
///   as one callback with nothing looking changed (Tech Architect 5647974743, 5648120868 NB1; 5646901449 NB1).
/// - Requests from the watch arrive as user info and go to the feature as they are; it settles them exactly once.
@MainActor
public final class PhoneWatchLink: WatchCompanionLink {
    private let session: any WatchContextSession
    private let now: () -> Date
    private var stamps = WatchPublishStamp()
    private var isActivated = false
    private var requestHandler: (@MainActor (Data) -> Void)?
    private var watchChangedHandler: (@MainActor () -> Void)?

    public init(session: any WatchContextSession, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    public func onRequest(_ handler: @escaping @MainActor (Data) -> Void) {
        requestHandler = handler
    }

    public func onWatchChanged(_ handler: @escaping @MainActor () -> Void) {
        watchChangedHandler = handler
    }

    /// `.waiting` until activation has completed and a paired watch has the app; the feature publishes again when
    /// either changes.
    public func publish(_ snapshot: Data) throws -> WatchPublishResult {
        guard isActivated, session.watchState.canReceive else {
            return .waiting
        }
        let context = WatchApplicationContext(snapshot: snapshot, stamp: stamps.next(now: now()))
        try session.updateApplicationContext(WatchLinkKeys.applicationContext(context))
        return .delivered
    }

    /// The session activated: from now on its state is known. With the app installed, the current snapshot goes
    /// out again, stamped, even if an identical one went before.
    public func activationCompleted() {
        isActivated = true
        if session.watchState.canReceive {
            watchChangedHandler?()
        }
    }

    /// The user switched to another watch; the adapter activates again, and `activationCompleted` follows.
    public func deactivated() {
        isActivated = false
    }

    /// `sessionWatchStateDidChange`: while the watch can receive, the current snapshot goes again, stamped, once
    /// for this callback, whatever changed. The flags can look unchanged after a removal and reinstall reported
    /// together (5648120868 NB1). With no watch to receive, nothing is sent.
    public func watchStateChanged() {
        guard isActivated, session.watchState.canReceive else {
            return
        }
        watchChangedHandler?()
    }

    /// A user-info transfer from the watch. Anything that isn't a request is ignored.
    public func received(userInfo: [String: Any]) {
        guard let request = WatchLinkKeys.request(in: userInfo) else {
            return
        }
        received(request: request)
    }

    /// The request the adapter read from a user-info transfer with `WatchLinkKeys.request(in:)`.
    public func received(request: Data) {
        requestHandler?(request)
    }
}

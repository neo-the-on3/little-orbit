import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import WatchConnectivity

/// The iPhone's WatchConnectivity adapter (#48, #197 item 10). It only wraps `WCSession` and forwards its events
/// to `PhoneWatchLink`, which holds the delivery rules: the snapshot is the application context, stamped on every
/// publish so a re-send to a newly installed watch app isn't dropped (Tester F1), and each Pay or Skip from the
/// watch arrives once as queued user info. No internet or iCloud. Domain and Features see `WatchCompanionLink`.
@MainActor
final class PhoneWatchSession: NSObject, WatchContextSession {
    private let session: WCSession?
    /// The link owns this adapter; the adapter only forwards to it.
    private weak var link: PhoneWatchLink?

    private init(session: WCSession?) {
        self.session = session
        super.init()
    }

    /// The link over the default session. Where WatchConnectivity isn't supported, such as on iPad, nothing is
    /// paired, so every publish waits.
    static func makeLink() -> PhoneWatchLink {
        let adapter = PhoneWatchSession(session: WCSession.isSupported() ? WCSession.default : nil)
        let link = PhoneWatchLink(session: adapter)
        adapter.link = link
        adapter.session?.delegate = adapter
        adapter.session?.activate()
        return link
    }

    var watchState: WatchSessionState {
        WatchSessionState(
            isPaired: session?.isPaired ?? false,
            isWatchAppInstalled: session?.isWatchAppInstalled ?? false,
        )
    }

    func updateApplicationContext(_ context: [String: Any]) throws {
        try session?.updateApplicationContext(context)
    }
}

extension PhoneWatchSession: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?,
    ) {
        guard activationState == .activated else {
            return
        }
        Task { @MainActor in self.link?.activationCompleted() }
    }

    /// A watch was paired or unpaired, or the watch app installed or removed.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.link?.watchStateChanged() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched to another watch: activate again for it.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in self.link?.deactivated() }
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let request = WatchLinkKeys.request(in: userInfo) else {
            return
        }
        Task { @MainActor in self.link?.received(request: request) }
    }
}

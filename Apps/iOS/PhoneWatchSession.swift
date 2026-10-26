import Foundation
import LittleOrbitDomain
import WatchConnectivity

/// The iPhone's WatchConnectivity adapter (#48, #197 item 10). The snapshot is the application context, so the
/// watch always reads the latest one, even after the iPhone app quits; each Pay or Skip from the watch arrives
/// once as queued user info. No internet or iCloud. Domain and Features see `WatchCompanionLink` only.
@MainActor
final class PhoneWatchSession: NSObject, WatchCompanionLink {
    private let session: WCSession?
    private var requestHandler: (@MainActor (Data) -> Void)?
    /// The snapshot to send once the session is active.
    private var waitingSnapshot: Data?

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func onRequest(_ handler: @escaping @MainActor (Data) -> Void) {
        requestHandler = handler
    }

    /// Before the session is active, the snapshot waits and goes out on activation. With no paired watch or no
    /// watch app installed, there's no one to send it to.
    func publish(_ snapshot: Data) throws {
        guard let session else {
            return
        }
        guard session.activationState == .activated else {
            waitingSnapshot = snapshot
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else {
            return
        }
        try session.updateApplicationContext([WatchLinkKeys.snapshot: snapshot])
    }

    private func activated() {
        guard let snapshot = waitingSnapshot else {
            return
        }
        waitingSnapshot = nil
        try? publish(snapshot)
    }

    private func received(_ request: Data) {
        requestHandler?(request)
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
        Task { @MainActor in self.activated() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched to another watch: activate again for it.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let request = userInfo[WatchLinkKeys.request] as? Data else {
            return
        }
        Task { @MainActor in self.received(request) }
    }
}

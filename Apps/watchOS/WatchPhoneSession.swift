import Foundation
import LittleOrbitDomain
import WatchConnectivity

/// The watch's WatchConnectivity adapter (#48, #197 item 10): it reads the iPhone's snapshot from the application
/// context and queues each Pay or Skip as user info, which the system delivers once, whenever the iPhone is
/// reachable. No internet, iCloud or App Group (D345). Domain and Features see `WatchPhoneLink` only.
@MainActor
final class WatchPhoneSession: NSObject, WatchPhoneLink {
    private let session = WCSession.default
    private var snapshotHandler: (@MainActor (Data) -> Void)?
    /// Requests tapped before the session finished activating; they're queued on activation.
    private var waitingRequests: [Data] = []

    override init() {
        super.init()
        session.delegate = self
        session.activate()
    }

    func latestSnapshotData() -> Data? {
        session.receivedApplicationContext[WatchLinkKeys.snapshot] as? Data
    }

    func onSnapshot(_ handler: @escaping @MainActor (Data) -> Void) {
        snapshotHandler = handler
    }

    func send(_ request: Data) {
        guard session.activationState == .activated else {
            waitingRequests.append(request)
            return
        }
        session.transferUserInfo([WatchLinkKeys.request: request])
    }

    private func activated() {
        let waiting = waitingRequests
        waitingRequests = []
        waiting.forEach(send)
        if let latest = latestSnapshotData() {
            snapshotHandler?(latest)
        }
    }

    private func received(_ snapshot: Data) {
        snapshotHandler?(snapshot)
    }
}

extension WatchPhoneSession: WCSessionDelegate {
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

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = applicationContext[WatchLinkKeys.snapshot] as? Data else {
            return
        }
        Task { @MainActor in self.received(snapshot) }
    }
}

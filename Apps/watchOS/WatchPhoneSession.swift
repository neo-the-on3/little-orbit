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
    private var finishedHandler: (@MainActor (UUID, Bool) -> Void)?
    private var retryHandler: (@MainActor () -> Void)?

    override init() {
        super.init()
        session.delegate = self
        session.activate()
    }

    func latestSnapshotData() -> Data? {
        WatchLinkKeys.snapshot(in: session.receivedApplicationContext)
    }

    func onSnapshot(_ handler: @escaping @MainActor (Data) -> Void) {
        snapshotHandler = handler
    }

    func onSendFinished(_ handler: @escaping @MainActor (UUID, Bool) -> Void) {
        finishedHandler = handler
    }

    func onCanRetry(_ handler: @escaping @MainActor () -> Void) {
        retryHandler = handler
    }

    /// Before activation nothing is queued: the use cases keep the request and send it again on activation. One the
    /// system is still delivering, from this launch or an earlier one, isn't queued twice (D377).
    func send(_ request: Data, id: UUID) -> WatchSendResult {
        guard session.activationState == .activated else {
            return .unavailable
        }
        let queued = session.outstandingUserInfoTransfers.contains { transfer in
            WatchLinkKeys.requestID(in: transfer.userInfo) == id
        }
        if !queued {
            session.transferUserInfo(WatchLinkKeys.userInfo(request: request, id: id))
        }
        return .inFlight
    }

    private func activated() {
        retryHandler?()
        if let latest = latestSnapshotData() {
            snapshotHandler?(latest)
        }
    }

    private func received(_ snapshot: Data) {
        snapshotHandler?(snapshot)
    }

    private func finished(_ id: UUID, delivered: Bool) {
        finishedHandler?(id, delivered)
    }

    private func reachable() {
        retryHandler?()
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
        // The publish stamp beside the snapshot is ignored (Tester F1).
        guard let snapshot = WatchLinkKeys.snapshot(in: applicationContext) else {
            return
        }
        Task { @MainActor in self.received(snapshot) }
    }

    /// The system finished a queued request: delivered, or failed with `error` (D377).
    nonisolated func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: (any Error)?,
    ) {
        guard let id = WatchLinkKeys.requestID(in: userInfoTransfer.userInfo) else {
            return
        }
        let delivered = error == nil
        Task { @MainActor in self.finished(id, delivered: delivered) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else {
            return
        }
        Task { @MainActor in self.reachable() }
    }
}

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
    private var watchChangedHandler: (@MainActor () -> Void)?
    /// The latest snapshot no watch could take yet: it goes out on activation, or when a watch is paired or the
    /// watch app is installed (Tech Architect 5646845418, B1).
    private var waitingSnapshot: Data?
    /// A held snapshot that the session refused when it finally went out; logged with no user data.
    private let onPublishFailed: @MainActor (any Error) -> Void

    init(onPublishFailed: @escaping @MainActor (any Error) -> Void = { _ in }) {
        session = WCSession.isSupported() ? WCSession.default : nil
        self.onPublishFailed = onPublishFailed
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func onRequest(_ handler: @escaping @MainActor (Data) -> Void) {
        requestHandler = handler
    }

    func onWatchChanged(_ handler: @escaping @MainActor () -> Void) {
        watchChangedHandler = handler
    }

    /// Until the session is active, a watch is paired and the watch app is installed, the snapshot waits here and
    /// the feature is told it wasn't delivered.
    func publish(_ snapshot: Data) throws -> WatchPublishResult {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled
        else {
            waitingSnapshot = snapshot
            return .waiting
        }
        try session.updateApplicationContext([WatchLinkKeys.snapshot: snapshot])
        waitingSnapshot = nil
        return .delivered
    }

    /// Activation finished, or the paired watch or its app changed: sends the held snapshot if it can go now, then
    /// lets the feature send the current one again, in case this is a watch that never got it (Tech Architect
    /// 5646901449, NB1).
    private func watchChanged() {
        if let snapshot = waitingSnapshot {
            do {
                _ = try publish(snapshot)
            } catch {
                onPublishFailed(error)
            }
        }
        watchChangedHandler?()
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
        Task { @MainActor in self.watchChanged() }
    }

    /// A watch was paired or unpaired, or the watch app installed or removed.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.watchChanged() }
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

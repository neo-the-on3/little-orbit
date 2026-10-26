import Foundation
import LittleOrbitDomain

/// The iPhone side of the watch's Scheduled screens (#197 item 10), built once by the composition root. It applies
/// the watch's Pay and Skip requests through the exactly-once path, reloads every window when one records
/// something, and sends the watch a new snapshot after every ledger change.
@MainActor
public final class WatchPhoneFeature {
    private let snapshots: any MakeWatchSnapshotUseCase
    private let requests: any ApplyWatchRequestsUseCase
    private let link: any WatchCompanionLink
    private let updates: LedgerUpdates?
    private let onProblem: (WatchLinkProblem) -> Void
    private var lastPublished: Data?
    /// The Scheduled list's card for requests it didn't apply (D374, D376), shared with `ScheduledFeature`.
    private let notices: WatchRequestNoticeViewModel?

    public init(
        snapshots: any MakeWatchSnapshotUseCase,
        requests: any ApplyWatchRequestsUseCase,
        link: any WatchCompanionLink,
        updates: LedgerUpdates? = nil,
        notices: WatchRequestNoticeViewModel? = nil,
        onProblem: @escaping (WatchLinkProblem) -> Void = { _ in },
    ) {
        self.snapshots = snapshots
        self.requests = requests
        self.link = link
        self.updates = updates
        self.onProblem = onProblem
        self.notices = notices
        link.onRequest { [weak self] data in self?.received(data) }
    }

    /// At launch and whenever the app becomes active: applies requests kept from a failed save, then publishes.
    public func start() {
        finish(requests.applyKept())
    }

    /// Sends the watch the current snapshot, unless it's the one it already has. The App calls it after every
    /// ledger change (`LedgerUpdates.revision`).
    public func publish() {
        let data: Data
        do {
            data = try WatchMessageCodec.encode(snapshots.snapshot())
        } catch {
            onProblem(.snapshotFailed(error))
            return
        }
        guard data != lastPublished else {
            return
        }
        do {
            try link.publish(data)
            lastPublished = data
        } catch {
            onProblem(.publishFailed(error))
        }
    }

    func received(_ data: Data) {
        let request: WatchScheduledRequest
        do {
            request = try WatchMessageCodec.decodeRequest(data)
        } catch .newerVersion {
            // Not applied or kept; answered so the watch clears its mark, with a card to update (D376).
            onProblem(.newerRequest)
            if let newer = WatchMessageCodec.newerRequest(data) {
                finish(requests.receiveNewer(newer))
            }
            return
        } catch {
            onProblem(.unreadableRequest)
            return
        }
        finish(requests.receive(request))
    }

    private func finish(_ run: WatchApplyRun) {
        if run.failedCount > 0 {
            onProblem(.someNotApplied)
        }
        if run.changedLedger {
            // Every window reloads, and the revision change publishes; publish now as well, in case none is open.
            updates?.changed()
        }
        if run.queuedNotices > 0 {
            notices?.reload()
        }
        publish()
    }
}

/// Why the watch link needs a log line. Never carries names, amounts or paths.
public enum WatchLinkProblem {
    case snapshotFailed(any Error)
    case publishFailed(any Error)
    /// A request the iPhone couldn't read.
    case unreadableRequest
    /// A request from a newer watch build.
    case newerRequest
    /// Some requests' saves failed; they're kept and tried again at the next activation.
    case someNotApplied
}

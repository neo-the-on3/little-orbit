import Foundation
import LittleOrbitDomain

@testable import LittleOrbitFeatures

/// A paired iPhone and watch over fakes that behave like `WCSession` where it matters (Tester F1, Tech Architect
/// 5647974743). The dictionaries are the real ones from `WatchLinkKeys`.
///
/// - The iPhone's session keeps the last application context and drops one identical to it as "no change".
/// - A context reaches the watch only if the watch app is really there, whatever the session's flag says.
/// - Removing the watch app loses what it had; the iPhone's session still remembers the context it sent.
/// - The watch's user-info transfers queue until `deliver`, which may repeat them, as the system can.
@MainActor
final class FakeWatchSessions: WatchContextSession, WatchPhoneLink {
    // MARK: iPhone side

    var watchState = WatchSessionState(isPaired: true, isWatchAppInstalled: true)
    /// Whether the watch app is really installed, which a stale flag before activation may not match.
    var watchHasApp = true
    private(set) var storedContext: NSDictionary?
    /// Contexts the session took, and identical ones it dropped.
    private(set) var accepted: [[String: Any]] = []
    private(set) var dropped = 0
    weak var phoneLink: PhoneWatchLink?

    func updateApplicationContext(_ context: [String: Any]) throws {
        let dictionary = context as NSDictionary
        guard dictionary != storedContext else {
            dropped += 1
            return
        }
        storedContext = dictionary
        accepted.append(context)
        if watchHasApp {
            watchContext = context
            snapshotHandler?(WatchLinkKeys.snapshot(in: context) ?? Data())
        }
    }

    /// The stamps of the contexts the session took, in order.
    var stamps: [Int64] {
        accepted.compactMap { ($0[WatchLinkKeys.stamp] as? NSNumber)?.int64Value }
    }

    /// The watch app is installed (or reinstalled) and the session says so.
    func installWatchApp() {
        watchHasApp = true
        watchState.isWatchAppInstalled = true
        phoneLink?.watchStateChanged()
    }

    /// The watch app is deleted and installed again, and the session reports both in one callback: the flags look
    /// the same before and after (Tech Architect 5648120868 NB1).
    func reinstallInOneCallback() {
        watchContext = nil
        phoneLink?.watchStateChanged()
    }

    /// The watch app is deleted: it loses its context, and the session says so.
    func removeWatchApp() {
        watchHasApp = false
        watchContext = nil
        watchState.isWatchAppInstalled = false
        phoneLink?.watchStateChanged()
    }

    // MARK: Watch side

    private(set) var watchContext: [String: Any]?
    private var snapshotHandler: (@MainActor (Data) -> Void)?
    private var finishedHandler: (@MainActor (UUID, Bool) -> Void)?
    private var retryHandler: (@MainActor () -> Void)?
    /// Queued user-info transfers, as the watch's session holds them until they finish.
    private(set) var outstanding: [[String: Any]] = []
    private(set) var transfers = 0
    var isWatchActive = true

    func latestSnapshotData() -> Data? {
        watchContext.flatMap(WatchLinkKeys.snapshot(in:))
    }

    func onSnapshot(_ handler: @escaping @MainActor (Data) -> Void) { snapshotHandler = handler }
    func onSendFinished(_ handler: @escaping @MainActor (UUID, Bool) -> Void) { finishedHandler = handler }
    func onCanRetry(_ handler: @escaping @MainActor () -> Void) { retryHandler = handler }

    /// As the watch adapter does: nothing before activation, and one queued transfer per request ID.
    func send(_ request: Data, id: UUID) -> WatchSendResult {
        guard isWatchActive else {
            return .unavailable
        }
        if !outstanding.contains(where: { WatchLinkKeys.requestID(in: $0) == id }) {
            outstanding.append(WatchLinkKeys.userInfo(request: request, id: id))
            transfers += 1
        }
        return .inFlight
    }

    /// The system delivers every queued transfer to the iPhone, `times` times each, then reports each finished.
    func deliver(times: Int = 1) {
        let batch = outstanding
        outstanding = []
        for userInfo in batch {
            for _ in 0..<times {
                phoneLink?.received(userInfo: userInfo)
            }
            if let id = WatchLinkKeys.requestID(in: userInfo) {
                finishedHandler?(id, true)
            }
        }
    }

    /// Every queued transfer fails, as with the iPhone away for too long.
    func failTransfers() {
        let batch = outstanding
        outstanding = []
        for userInfo in batch {
            if let id = WatchLinkKeys.requestID(in: userInfo) {
                finishedHandler?(id, false)
            }
        }
    }

    /// The iPhone became reachable, or the watch's session activated.
    func canRetry() { retryHandler?() }
}

import Foundation

/// A Pay or Skip the watch sent, with a copy of the row it was tapped on (for the message if the iPhone turns it
/// down), and the iPhone's answer once a snapshot brings it.
public struct WatchSentRequest: Codable, Hashable, Sendable, Identifiable {
    public var request: WatchScheduledRequest
    public var occurrence: WatchScheduledOccurrence
    public var result: WatchRequestResult?
    /// The system confirmed it reached the iPhone, so it's never sent again (D377).
    public var isDelivered: Bool
    /// Failed deliveries in a row. Each one makes the next retry wait longer, up to a ceiling; the request is never
    /// dropped (D377).
    public var failures: Int
    /// No retry before this, after a failed delivery.
    public var retryAfter: Date?

    public init(
        request: WatchScheduledRequest,
        occurrence: WatchScheduledOccurrence,
        result: WatchRequestResult? = nil,
        isDelivered: Bool = false,
        failures: Int = 0,
        retryAfter: Date? = nil,
    ) {
        self.request = request
        self.occurrence = occurrence
        self.result = result
        self.isDelivered = isDelivered
        self.failures = failures
        self.retryAfter = retryAfter
    }

    public var id: UUID { request.id }

    /// Sent, and the iPhone hasn't answered yet: the row shows it as syncing.
    public var isPending: Bool { result == nil }

    private enum CodingKeys: String, CodingKey {
        case request, occurrence, result, isDelivered, failures, retryAfter
    }

    /// A cache written before D377 has no delivery fields: its requests count as not delivered yet.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = try container.decode(WatchScheduledRequest.self, forKey: .request)
        occurrence = try container.decode(WatchScheduledOccurrence.self, forKey: .occurrence)
        result = try container.decodeIfPresent(WatchRequestResult.self, forKey: .result)
        isDelivered = try container.decodeIfPresent(Bool.self, forKey: .isDelivered) ?? false
        failures = try container.decodeIfPresent(Int.self, forKey: .failures) ?? 0
        retryAfter = try container.decodeIfPresent(Date.self, forKey: .retryAfter)
    }
}

/// How often the watch retries a request whose delivery failed (D377): it waits twice as long after each failure
/// in a row, from `first` up to `ceiling`, and never gives up.
public enum WatchRetryPolicy {
    public static let first: TimeInterval = 10
    public static let ceiling: TimeInterval = 15 * 60

    public static func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else {
            return 0
        }
        let doublings = min(failures - 1, 16)
        return min(first * Double(1 << doublings), ceiling)
    }
}

/// What the watch's Scheduled screen reads: the last snapshot from the iPhone, if any, and the requests it sent
/// that are still syncing or were turned down.
public struct WatchScheduledState: Equatable, Sendable {
    public var snapshot: WatchSnapshot?
    public var sent: [WatchSentRequest]

    public init(snapshot: WatchSnapshot? = nil, sent: [WatchSentRequest] = []) {
        self.snapshot = snapshot
        self.sent = sent
    }
}

/// The watch's Scheduled screen (#197 item 10): read the list, Pay or Skip an occurrence, and close a message.
@MainActor
public protocol WatchScheduledUseCase: AnyObject {
    func state() -> WatchScheduledState
    func pay(_ occurrence: WatchScheduledOccurrence)
    func skip(_ occurrence: WatchScheduledOccurrence)
    /// The user closed the message for a request the iPhone turned down.
    func acknowledge(requestID: UUID)
    /// The watch app opened or became active: sends any request not delivered yet whose retry is due (D377).
    func retryPending()
    /// Called after every change to `state()`: a new snapshot, or a request sent or closed.
    func onChange(_ handler: @escaping @MainActor () -> Void)
}

/// The watch's end of WatchConnectivity. The App's adapter wraps `WCSession`; the system queues requests while
/// the iPhone is away and delivers each one once.
@MainActor
public protocol WatchPhoneLink: AnyObject {
    /// The last snapshot the iPhone sent, if the system still has it.
    func latestSnapshotData() -> Data?
    /// Called with each snapshot the iPhone sends.
    func onSnapshot(_ handler: @escaping @MainActor (Data) -> Void)
    /// Queues a request for the iPhone. `.inFlight` once the system has it, including when it already had it, so a
    /// request is never queued twice; `.unavailable` before the session is active.
    func send(_ request: Data, id: UUID) -> WatchSendResult
    /// Called when a queued request finished: delivered to the iPhone (`true`) or failed.
    func onSendFinished(_ handler: @escaping @MainActor (UUID, Bool) -> Void)
    /// Called when the session activates and when the iPhone becomes reachable: a time to retry.
    func onCanRetry(_ handler: @escaping @MainActor () -> Void)
}

/// Whether the link took a request (D377).
public enum WatchSendResult: Sendable {
    /// Queued with the system, which delivers it once.
    case inFlight
    /// The session isn't active yet; the request waits in the cache.
    case unavailable
}

/// A disposable cache on the watch: the last snapshot and the sent requests. Losing it loses no ledger data, since
/// the iPhone sends a new snapshot and the system still delivers anything queued.
@MainActor
public protocol WatchScheduledCache: AnyObject {
    func snapshotData() -> Data?
    func setSnapshotData(_ data: Data?)
    func sentRequests() -> [WatchSentRequest]
    func setSentRequests(_ requests: [WatchSentRequest])
}

/// A cache for one run only: tests and previews.
@MainActor
public final class InMemoryWatchScheduledCache: WatchScheduledCache {
    private var data: Data?
    private var requests: [WatchSentRequest] = []

    public init() {}

    public func snapshotData() -> Data? { data }
    public func setSnapshotData(_ data: Data?) { self.data = data }
    public func sentRequests() -> [WatchSentRequest] { requests }
    public func setSentRequests(_ requests: [WatchSentRequest]) { self.requests = requests }
}

/// The watch's Scheduled use cases over the link and the cache. `today` is the watch's day, the day a Pay is dated.
@MainActor
public final class DefaultWatchScheduledUseCases: WatchScheduledUseCase {
    private let link: any WatchPhoneLink
    private let cache: any WatchScheduledCache
    private let today: @MainActor () -> CalendarDay
    private let now: @MainActor () -> Date
    /// Runs the action after the delay: the App's timer. A retry also happens on every trigger once it's due.
    private let schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private var current: WatchScheduledState
    private var handlers: [@MainActor () -> Void] = []
    /// Requests the system is delivering now: at most one send per request (D377).
    private var inFlight: Set<UUID> = []

    public init(
        link: any WatchPhoneLink,
        cache: any WatchScheduledCache,
        today: @escaping @MainActor () -> CalendarDay,
        now: @escaping @MainActor () -> Date = { Date() },
        schedule: @escaping @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = { _, _ in },
    ) {
        self.link = link
        self.cache = cache
        self.today = today
        self.now = now
        self.schedule = schedule
        // An unreadable or newer cached snapshot is dropped: the next one from the iPhone replaces it.
        let cached = cache.snapshotData().flatMap { try? WatchMessageCodec.decodeSnapshot($0) }
        current = WatchScheduledState(snapshot: cached, sent: cache.sentRequests())
        link.onSnapshot { [weak self] data in self?.received(data) }
        // Queued requests stay in the cache until delivered, and go out again on activation, when the iPhone becomes
        // reachable and when the app opens (D377; Tech Architect 5646845418, NB1).
        link.onCanRetry { [weak self] in self?.retryPending() }
        link.onSendFinished { [weak self] id, delivered in self?.finished(id, delivered: delivered) }
        if let latest = link.latestSnapshotData() {
            received(latest, notify: false)
        }
    }

    public func state() -> WatchScheduledState {
        current
    }

    public func retryPending() {
        for sent in current.sent {
            deliver(sent.id)
        }
    }

    /// Hands one request to the link, unless it's delivered or answered, already in flight, or waiting out its
    /// backoff.
    private func deliver(_ id: UUID) {
        guard let sent = current.sent.first(where: { $0.id == id }),
            sent.isPending, !sent.isDelivered, !inFlight.contains(id),
            sent.retryAfter.map({ $0 <= now() }) ?? true,
            let data = try? WatchMessageCodec.encode(sent.request)
        else {
            return
        }
        if link.send(data, id: id) == .inFlight {
            inFlight.insert(id)
        }
    }

    /// Delivered: never sent again, and the row syncs until the iPhone's answer. Failed: kept, and retried after
    /// a longer wait each time (D377).
    private func finished(_ id: UUID, delivered: Bool) {
        inFlight.remove(id)
        guard let index = current.sent.firstIndex(where: { $0.id == id }) else {
            return
        }
        if delivered {
            current.sent[index].isDelivered = true
            current.sent[index].failures = 0
            current.sent[index].retryAfter = nil
            cache.setSentRequests(current.sent)
            return
        }
        current.sent[index].failures += 1
        let delay = WatchRetryPolicy.delay(afterFailures: current.sent[index].failures)
        current.sent[index].retryAfter = now().addingTimeInterval(delay)
        cache.setSentRequests(current.sent)
        schedule(delay) { [weak self] in self?.deliver(id) }
    }

    public func pay(_ occurrence: WatchScheduledOccurrence) {
        send(.pay, occurrence)
    }

    public func skip(_ occurrence: WatchScheduledOccurrence) {
        send(.skip, occurrence)
    }

    public func acknowledge(requestID: UUID) {
        current.sent.removeAll { $0.id == requestID && !$0.isPending }
        cache.setSentRequests(current.sent)
        notify()
    }

    public func onChange(_ handler: @escaping @MainActor () -> Void) {
        handlers.append(handler)
    }

    /// A snapshot from the iPhone replaces the cached one whole, and brings the answers to sent requests. Applied
    /// ones and ones the iPhone couldn't read go; turned-down ones stay until their message is closed. One that
    /// can't be read, or is from a newer iPhone build, is ignored and the cache is kept.
    func received(_ data: Data, notify shouldNotify: Bool = true) {
        guard let snapshot = try? WatchMessageCodec.decodeSnapshot(data) else {
            return
        }
        cache.setSnapshotData(data)
        current.snapshot = snapshot
        let answers = Dictionary(snapshot.outcomes.map { ($0.requestID, $0.result) }, uniquingKeysWith: { $1 })
        current.sent = current.sent.compactMap { sent in
            guard sent.isPending, let result = answers[sent.id] else {
                return sent
            }
            guard result.isConflict else {
                // Applied: the new snapshot shows the result. Stale or unsupported: nothing happened, and the
                // snapshot shows the occurrence as the iPhone has it.
                return nil
            }
            var answered = sent
            answered.result = result
            return answered
        }
        cache.setSentRequests(current.sent)
        if shouldNotify {
            notify()
        }
    }

    private func send(_ action: WatchScheduledRequest.Action, _ occurrence: WatchScheduledOccurrence) {
        // One request per occurrence at a time: a second tap while it syncs does nothing.
        guard !current.sent.contains(where: { $0.isPending && $0.request.occurrenceKey == occurrence.id }) else {
            return
        }
        let request = WatchScheduledRequest(
            action: action,
            itemID: occurrence.itemID,
            occurrence: occurrence.day,
            tappedOn: today(),
            revision: occurrence.revision,
        )
        current.sent.append(WatchSentRequest(request: request, occurrence: occurrence))
        cache.setSentRequests(current.sent)
        deliver(request.id)
        notify()
    }

    private func notify() {
        for handler in handlers {
            handler()
        }
    }
}

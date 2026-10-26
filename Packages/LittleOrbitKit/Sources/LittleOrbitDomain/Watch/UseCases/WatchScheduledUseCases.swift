import Foundation

/// A Pay or Skip the watch sent, with a copy of the row it was tapped on (for the message if the iPhone turns it
/// down), and the iPhone's answer once a snapshot brings it.
public struct WatchSentRequest: Codable, Hashable, Sendable, Identifiable {
    public var request: WatchScheduledRequest
    public var occurrence: WatchScheduledOccurrence
    public var result: WatchRequestResult?

    public init(
        request: WatchScheduledRequest,
        occurrence: WatchScheduledOccurrence,
        result: WatchRequestResult? = nil,
    ) {
        self.request = request
        self.occurrence = occurrence
        self.result = result
    }

    public var id: UUID { request.id }

    /// Sent, and the iPhone hasn't answered yet: the row shows it as syncing.
    public var isPending: Bool { result == nil }
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
    /// Queues a request for the iPhone.
    func send(_ request: Data)
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
    private var current: WatchScheduledState
    private var handlers: [@MainActor () -> Void] = []

    public init(
        link: any WatchPhoneLink,
        cache: any WatchScheduledCache,
        today: @escaping @MainActor () -> CalendarDay,
    ) {
        self.link = link
        self.cache = cache
        self.today = today
        // An unreadable or newer cached snapshot is dropped: the next one from the iPhone replaces it.
        let cached = cache.snapshotData().flatMap { try? WatchMessageCodec.decodeSnapshot($0) }
        current = WatchScheduledState(snapshot: cached, sent: cache.sentRequests())
        link.onSnapshot { [weak self] data in self?.received(data) }
        if let latest = link.latestSnapshotData() {
            received(latest, notify: false)
        }
    }

    public func state() -> WatchScheduledState {
        current
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
        guard let data = try? WatchMessageCodec.encode(request) else {
            return
        }
        current.sent.append(WatchSentRequest(request: request, occurrence: occurrence))
        cache.setSentRequests(current.sent)
        link.send(data)
        notify()
    }

    private func notify() {
        for handler in handlers {
            handler()
        }
    }
}

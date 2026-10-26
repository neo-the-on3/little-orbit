import Foundation

/// Builds the snapshot the iPhone sends the watch (#197 item 10).
@MainActor
public protocol MakeWatchSnapshotUseCase {
    func snapshot() throws -> WatchSnapshot
}

/// Applies the watch's Pay and Skip requests on the iPhone, each through the exactly-once Pay and Skip path.
/// They aren't Undo steps on the iPhone (#197 item 4 criteria).
@MainActor
public protocol ApplyWatchRequestsUseCase {
    /// Keeps `request` until it's applied, then applies everything kept. A request the iPhone has already answered
    /// isn't applied again; its outcome is reported again.
    @discardableResult
    func receive(_ request: WatchScheduledRequest) -> WatchApplyRun
    /// Applies what's kept, for the launch and for the app becoming active: a request whose save failed is tried
    /// again then.
    @discardableResult
    func applyKept() -> WatchApplyRun
    /// A request from a newer watch build, which this build can't apply (D376).
    @discardableResult
    func receiveNewer(_ request: WatchNewerRequest) -> WatchApplyRun
}

/// What one run of the kept requests did.
public struct WatchApplyRun: Equatable, Sendable {
    /// The answer to each request in the run, including ones answered before and delivered again.
    public var outcomes: [WatchRequestOutcome]
    /// Requests whose save failed; they're kept and tried again at the next run.
    public var failedCount: Int
    /// Whether this run recorded or skipped something, so the screens reload and a new snapshot goes out.
    public var changedLedger: Bool
    /// How many requests this run queued a notice for (D374, D376), so the Scheduled list shows it.
    public var queuedNotices: Int

    public init(
        outcomes: [WatchRequestOutcome] = [],
        failedCount: Int = 0,
        changedLedger: Bool = false,
        queuedNotices: Int = 0,
    ) {
        self.outcomes = outcomes
        self.failedCount = failedCount
        self.changedLedger = changedLedger
        self.queuedNotices = queuedNotices
    }
}

/// Where the iPhone keeps the watch requests it hasn't applied yet, the outcomes it reports back and the notices
/// not dismissed yet (D374, D376): app settings, not the ledger, so no backup holds them and the store's schema
/// doesn't change. IDs and days only.
@MainActor
public protocol WatchRequestInboxStore: AnyObject {
    func keptRequests() -> [WatchScheduledRequest]
    func setKeptRequests(_ requests: [WatchScheduledRequest])
    func outcomes() -> [WatchRequestOutcome]
    func setOutcomes(_ outcomes: [WatchRequestOutcome])
    func notices() -> [WatchRequestNotice]
    func setNotices(_ notices: [WatchRequestNotice])
}

/// An inbox for one run only: tests and previews.
@MainActor
public final class InMemoryWatchRequestInboxStore: WatchRequestInboxStore {
    private var requests: [WatchScheduledRequest] = []
    private var answered: [WatchRequestOutcome] = []
    private var pending: [WatchRequestNotice] = []

    public init() {}

    public func keptRequests() -> [WatchScheduledRequest] { requests }
    public func setKeptRequests(_ requests: [WatchScheduledRequest]) { self.requests = requests }
    public func outcomes() -> [WatchRequestOutcome] { answered }
    public func setOutcomes(_ outcomes: [WatchRequestOutcome]) { answered = outcomes }
    public func notices() -> [WatchRequestNotice] { pending }
    public func setNotices(_ notices: [WatchRequestNotice]) { pending = notices }
}

/// The iPhone side of the watch link over the scheduled repository. `today` is the Scheduled screens' today.
@MainActor
public struct DefaultWatchPhoneUseCases: MakeWatchSnapshotUseCase, ApplyWatchRequestsUseCase {
    /// How many answered requests are remembered, so a late duplicate is recognised rather than re-applied. The
    /// ledger's occurrence key already stops a second recording; this keeps the watch's message right.
    public static let rememberedOutcomes = 200

    let repository: any ScheduleRepository
    let inbox: any WatchRequestInboxStore
    private let today: @MainActor () -> CalendarDay

    public init(
        repository: any ScheduleRepository,
        inbox: any WatchRequestInboxStore,
        today: @escaping @MainActor () -> CalendarDay,
    ) {
        self.repository = repository
        self.inbox = inbox
        self.today = today
    }

    // MARK: Snapshot

    public func snapshot() throws -> WatchSnapshot {
        let ledger = try repository.scheduleLedger()
        let day = today()
        let board = ScheduledBoard.make(ledger, today: day)
        let rows =
            board.overdue.map { occurrence($0, .overdue, in: ledger) }
            + board.dueToday.map { occurrence($0, .dueToday, in: ledger) }
            + board.upcoming.map { occurrence($0, .upcoming, in: ledger) }
        return WatchSnapshot(
            today: day,
            scheduled: rows,
            outcomes: Array(inbox.outcomes().suffix(WatchMessageCodec.maxOutcomes)),
        )
    }

    private func occurrence(
        _ due: ScheduledDue,
        _ status: WatchScheduledStatus,
        in ledger: LedgerSnapshot,
    ) -> WatchScheduledOccurrence {
        let item = due.item
        let account = ledger.accounts.first { $0.id == item.accountID }
        let details = item.details?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WatchScheduledOccurrence(
            itemID: item.id,
            day: due.day,
            status: status,
            type: item.type,
            amount: item.amount,
            currencyCode: account?.currencyCode ?? CurrencyCode.deviceDefault,
            details: details?.isEmpty == false ? details : nil,
            payeeName: ledger.payees.first { $0.id == item.payeeID }?.name,
            categoryName: ledger.categories.first { $0.id == item.categoryID }?.name,
            accountName: account?.name ?? "",
            transferAccountName: ledger.accounts.first { $0.id == item.transferAccountID }?.name,
            revision: WatchItemRevision.of(item),
        )
    }

    // MARK: Requests

    @discardableResult
    public func receive(_ request: WatchScheduledRequest) -> WatchApplyRun {
        var kept = inbox.keptRequests()
        if !kept.contains(where: { $0.id == request.id }) {
            kept.append(request)
            inbox.setKeptRequests(kept)
        }
        return applyKept()
    }

    @discardableResult
    public func applyKept() -> WatchApplyRun {
        var run = WatchApplyRun()
        var stillKept: [WatchScheduledRequest] = []
        var answered = inbox.outcomes()
        var notices: [WatchRequestNotice] = []
        for request in inbox.keptRequests() {
            let result: WatchRequestResult
            if let earlier = answered.first(where: { $0.requestID == request.id }) {
                // Delivered again: the first answer stands, and nothing is applied twice.
                run.outcomes.append(WatchRequestOutcome(requestID: request.id, result: earlier.result))
                continue
            }
            do {
                result = try apply(request)
            } catch {
                run.failedCount += 1
                stillKept.append(request)
                continue
            }
            let outcome = WatchRequestOutcome(requestID: request.id, result: result)
            run.changedLedger = run.changedLedger || result == .applied
            // Shown on the Scheduled list until dismissed (D374, D376).
            if let reason = Self.noticeReason(result) {
                notices.append(
                    WatchRequestNotice(id: request.id, reason: reason, action: request.action, itemID: request.itemID)
                )
            }
            answered.append(outcome)
            run.outcomes.append(outcome)
        }
        inbox.setKeptRequests(stillKept)
        inbox.setOutcomes(Array(answered.suffix(Self.rememberedOutcomes)))
        notices.forEach(queue)
        run.queuedNotices = notices.count
        return run
    }

    private static func noticeReason(_ result: WatchRequestResult) -> WatchRequestNotice.Reason? {
        switch result {
        case .stale: .itemChanged
        case .unsupported: .newerWatchApp
        case .applied, .alreadyPaid, .alreadySkipped, .deleted: nil
        }
    }

    /// One request, through `ScheduleRepository.settleScheduledOccurrence`, the path Pay Now and Skip use. What the
    /// iPhone already did to the occurrence wins: a paid or skipped one stays as it is (#32 QA, D342, D343). A
    /// request made against an item changed on the iPhone since is stale and settles nothing, on its own day or
    /// any other (D374).
    private func apply(_ request: WatchScheduledRequest) throws -> WatchRequestResult {
        guard request.version <= WatchSnapshot.currentVersion else {
            return .unsupported
        }
        let ledger = try repository.scheduleLedger()
        guard let item = LedgerBook.activeScheduledItems(in: ledger).first(where: { $0.id == request.itemID }) else {
            return .deleted
        }
        if let settled = item.occurrence(on: request.occurrence), settled.outcome.isSettled {
            return settled.outcome == .posted ? .alreadyPaid : .alreadySkipped
        }
        if let revision = request.revision, revision != WatchItemRevision.of(item) {
            return .stale
        }
        do {
            _ = try repository.settleScheduledOccurrence(request.settlement)
        } catch LedgerValidationError.missingScheduledItem {
            return .deleted
        } catch LedgerValidationError.notAnOccurrence {
            return .stale
        }
        return .applied
    }
}

/// The iPhone's end of WatchConnectivity. The App's adapter wraps `WCSession`: the snapshot is the application
/// context (only the latest is kept), and each watch request arrives once as queued user info.
@MainActor
public protocol WatchCompanionLink: AnyObject {
    /// Called with each request the watch sends.
    func onRequest(_ handler: @escaping @MainActor (Data) -> Void)
    /// Replaces the snapshot the watch reads. Throws when the session can't take it (no paired watch, say).
    func publish(_ snapshot: Data) throws
}

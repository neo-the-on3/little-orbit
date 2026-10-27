import Foundation
import LittleOrbitCore
import Observation

/// What a window's undo history needs from the window's `UndoManager` (`@Environment(\.undoManager)`). The
/// `UndoManager` holds the window's steps; the history registers each one on it and nothing else (D187.2).
/// The tests use a stand-in, because Linux, where CI also runs them, has no `UndoManager`.
@MainActor
public protocol UndoRegistrar: AnyObject {
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    var isUndoing: Bool { get }
    var isRedoing: Bool { get }
    /// How many groups are open; 0 between events.
    var groupingLevel: Int { get }
    /// The newest Undo and Redo names, "" when there are none.
    var undoActionName: String { get }
    var redoActionName: String { get }
    /// Registers one undoable step for `target` with its name: on Undo while not undoing, on Redo while
    /// undoing, as `UndoManager` does.
    func registerStep(_ target: AnyObject, named name: String, handler: @escaping @MainActor () -> Void)
    /// Removes every Undo and Redo step registered for `target`.
    func removeSteps(for target: AnyObject)
    func undo()
    func redo()
    /// Calls `onChange` after the Undo or Redo lists may have changed: a group opened or closed, an Undo or a
    /// Redo. Never on a checkpoint, which merely reading `canUndo` or `canRedo` posts (B1). The result keeps
    /// the observation alive; dropping it stops it.
    func observeChanges(_ onChange: @escaping @MainActor (UndoEvent) -> Void) -> AnyObject
}

/// What happened on a window's `UndoManager`, from its notifications.
public enum UndoEvent: Equatable, Sendable {
    case openedGroup
    case closedGroup
    case undid
    case redid
}

#if canImport(Darwin)
    extension UndoManager: UndoRegistrar {
        public func registerStep(
            _ target: AnyObject,
            named name: String,
            handler: @escaping @MainActor () -> Void,
        ) {
            // The window's own settings, grouping by event included, are left as the system set them.
            registerUndo(withTarget: target) { _ in
                MainActor.assumeIsolated { handler() }
            }
            setActionName(name)
        }

        public func removeSteps(for target: AnyObject) {
            removeAllActions(withTarget: target)
        }

        public func observeChanges(_ onChange: @escaping @MainActor (UndoEvent) -> Void) -> AnyObject {
            // Not `NSUndoManagerCheckpoint`: reading `canUndo` or `canRedo` posts it, so a toolbar that read them
            // and redrew on it would never stop (Tester's B1 on #87).
            let events: [(Notification.Name, UndoEvent)] = [
                (.NSUndoManagerDidOpenUndoGroup, .openedGroup),
                (.NSUndoManagerDidCloseUndoGroup, .closedGroup),
                (.NSUndoManagerDidUndoChange, .undid),
                (.NSUndoManagerDidRedoChange, .redid),
            ]
            let center = NotificationCenter.default
            let tokens = events.map { name, event in
                center.addObserver(forName: name, object: self, queue: nil) { _ in
                    MainActor.assumeIsolated { onChange(event) }
                }
            }
            return UndoObservation(tokens: tokens)
        }
    }

    /// Removes the notification observers when the window's history lets go of it.
    final class UndoObservation {
        private let tokens: [any NSObjectProtocol]

        init(tokens: [any NSObjectProtocol]) {
            self.tokens = tokens
        }

        deinit {
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }
#endif

/// Moves on after every change to the one shared store from any window, so every window's lists and
/// balances reload straight away (D187.4). Built once, at App level.
@MainActor
@Observable
public final class LedgerUpdates {
    public private(set) var revision = 0
    /// A Bulk Edit, or its Undo or Redo, is being built or saved in some window. Until it ends, every window's
    /// ledger writes are off, Undo and Redo included; nothing queues (#285, D398).
    public private(set) var isBatchRunning = false
    /// When the last batch ran, start to end, on the `systemUptime` clock, for `dropsQueuedCommand` (Tester2,
    /// c8c6594; review 5666694381). The same clock as the events' timestamps and the press time
    /// (`QueuedCommandPolicy`), so they compare directly (Tech Architect's condition 4 on 3dc318b).
    @ObservationIgnored private(set) var lastBatch: ClosedRange<TimeInterval>?
    /// When the batch running now started.
    @ObservationIgnored private var batchStart: TimeInterval?
    /// The event whose command was dropped last: it drops no other.
    @ObservationIgnored private var lastDroppedEventTime: TimeInterval?
    /// The press whose command was dropped last: it drops no other.
    @ObservationIgnored private var lastDroppedPressTime: TimeInterval?
    /// The newest event an Undo or Redo was handled with, so an older or the same one is stale (condition 1).
    @ObservationIgnored private var lastCommandEventTime: TimeInterval?
    /// The current event when the last batch ended, so one dispatched before the end, which no command consumed,
    /// is stale too (Tech Architect's B4 on 0d676f8).
    @ObservationIgnored private(set) var eventTimeAtEnd: TimeInterval?
    /// The `systemUptime` clock; tests set it.
    @ObservationIgnored var uptime: @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// When the app started, on that clock: a press time before it is wrong, and drops nothing; tests set it.
    @ObservationIgnored var launchUptime = ProcessInfo.processInfo.systemUptime
    /// The event being handled; tests set it.
    @ObservationIgnored var currentEvent: @MainActor () -> QueuedCommandPolicy.Event? = QueuedCommandPolicy.currentEvent
    /// Seconds since the left mouse button last went down: the event source on the Mac, `nil` on iOS; tests set it.
    @ObservationIgnored var secondsSincePress: @MainActor () -> Double? = QueuedCommandPolicy.secondsSinceLeftMouseDown
    /// Window refreshes running now, by the revision of the change that started them (`refreshStarted(for:)`), so
    /// a batch ends once its own change's refreshes are done, and one still running for an earlier change, in any
    /// window, doesn't hold it (Tech Architect on 0d676f8).
    @ObservationIgnored private var runningRefreshes: [Int: Int] = [:]
    /// Every window refresh running now, for any change.
    var refreshesRunning: Int { runningRefreshes.values.reduce(0, +) }
    /// How `settle()` waits; tests may step it by hand.
    @ObservationIgnored var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    /// `settle()` calls waiting for the refreshes of a change, from its revision on, to end, by id.
    @ObservationIgnored private var settleWaiters:
        [UUID: (revision: Int, continuation: CheckedContinuation<Bool, Never>)] =
            [:]
    @ObservationIgnored private var histories: [WeakHistory] = []
    /// Every window's account history, held weakly, so a change starts their refreshes as it's posted (B2).
    @ObservationIgnored private var registers: [WeakRegister] = []
    @ObservationIgnored private var replacedHandlers: [(id: UUID, run: @MainActor () -> Void)] = []
    @ObservationIgnored private var changedHandlers: [@MainActor () -> Void] = []
    /// What each recent revision touched, newest last, so a window that saw an earlier one can tell what it missed.
    @ObservationIgnored private var deltas: [(revision: Int, delta: LedgerDelta)] = []
    /// Revisions kept in `deltas`; a window further behind reloads everything.
    static let deltaHistory = 32

    private struct WeakHistory {
        weak var history: WindowUndoHistory?
    }

    private struct WeakRegister {
        weak var model: AccountHistoryViewModel?
    }

    public init() {}

    /// Starts a batch: writes go off in every window. `false` when one is already running, which starts nothing.
    func beginBatch() -> Bool {
        guard !isBatchRunning else {
            return false
        }
        isBatchRunning = true
        let start = uptime()
        batchStart = start
        BatchTrace.event("ledger.batch.start", value: start)
        refreshHistories()
        return true
    }

    /// Ends the batch, recording its end now. A batch Undo or Redo calls it once its change has been posted, every
    /// window has refreshed and the main actor is free again (`settle()`), so the busy flag and the drop window cover
    /// everything the user sees as busy (D403.1; Tester2 on 1f2eae8). Bulk Edit's Apply ends the same way (D403 on 3dc318b).
    func endBatch() {
        guard isBatchRunning else {
            return
        }
        isBatchRunning = false
        let end = uptime()
        lastBatch = min(batchStart ?? end, end)...end
        // A click or key press dispatched while the batch ran, which no Undo or Redo was handled with, is still the
        // current event after it. A VoiceOver or Voice Control Undo or Redo then sees it, and it mustn't count (B4).
        // A queued command's own event is dispatched after this, so it's newer and the batch's rules still apply.
        eventTimeAtEnd = currentEvent()?.time
        BatchTrace.event("ledger.batch.end", value: end)
        batchStart = nil
        refreshHistories()
    }

    /// The longest `settle()` waits for window refreshes, so a refresh that never ends can't hold busy on for good.
    static let settleLimit = Duration.seconds(2)

    /// After a change was posted: waits until every refresh it started has ended (`settleLimit` at most), then one
    /// turn of the main run loop, so the table updates that follow them have been committed and the main actor is
    /// free. `changed(_:)` starts and counts each window's refresh before it returns, so there's nothing to guess at
    /// (Tech Architect's B2 on 0389f40). Signposted as `ledger.settle`; `true`, and a `ledger.settle.limit` event,
    /// if it stopped at `settleLimit`.
    @discardableResult
    func settle() async -> Bool {
        let span = BatchTrace.begin("ledger.settle")
        defer { span.end() }
        // The change just posted: only its refreshes, or a later change's, hold the batch.
        let change = revision
        var reachedLimit = false
        if isRefreshing(from: change) {
            let id = UUID()
            let limit = Task { [weak self] in
                await self?.sleep(Self.settleLimit)
                self?.resumeSettle(id, reachedLimit: true)
            }
            reachedLimit = await withCheckedContinuation { continuation in
                // The count is read again in the same main-actor step that starts the wait, so a refresh that ended
                // in between can't leave it waiting for a wake-up already given. Each waiter is resumed once: by the
                // last refresh's end or by the cap, whichever takes it from `settleWaiters` first.
                guard isRefreshing(from: change) else {
                    continuation.resume(returning: false)
                    return
                }
                settleWaiters[id] = (change, continuation)
            }
            limit.cancel()
        }
        if reachedLimit {
            // The batch ends with refreshes still running, how many as the value (m3 on 0389f40).
            BatchTrace.event("ledger.settle.limit", value: Double(refreshesRunning))
        }
        await sleep(BatchProgress.uiTurnLength)
        return reachedLimit
    }

    private func resumeSettle(_ id: UUID, reachedLimit: Bool) {
        settleWaiters.removeValue(forKey: id)?.continuation.resume(returning: reachedLimit)
    }

    /// Whether a refresh for the change at `revision`, or a later one, is running.
    private func isRefreshing(from revision: Int) -> Bool {
        runningRefreshes.keys.contains { $0 >= revision }
    }

    /// A window's refresh after the change at `revision` started, the current one by default; `refreshEnded(for:)`
    /// with the same revision when it's done.
    func refreshStarted(for revision: Int? = nil) {
        runningRefreshes[revision ?? self.revision, default: 0] += 1
    }

    /// A refresh for the change at `revision` ended; by default the newest change's that's running. Each `settle()`
    /// whose change has no refresh running any more goes on, resumed once.
    func refreshEnded(for revision: Int? = nil) {
        guard let key = revision ?? runningRefreshes.keys.max(), let count = runningRefreshes[key] else {
            return
        }
        runningRefreshes[key] = count > 1 ? count - 1 : nil
        let done = settleWaiters.filter { !isRefreshing(from: $0.value.revision) }
        for (id, waiter) in done {
            settleWaiters.removeValue(forKey: id)
            waiter.continuation.resume(returning: false)
        }
    }

    /// Whether the command being handled was asked for while the last batch ran, so it waited in the event queue
    /// while the save blocked the main thread: an Undo or Redo then does nothing (`QueuedCommandPolicy`). A `true`
    /// uses up the event, or for the mouse the press, so the next command it's seen with goes through.
    ///
    /// Signposted on every check: `ledger.command.press` with the press time (-1 for none, or one that can't be
    /// right), `ledger.command.pressAge` with the event source's raw seconds since it (-1 for no source), then
    /// `ledger.command.dropped` or `.passed` with the event's time (-1 for none, or a stale one).
    func dropsQueuedCommand() -> Bool {
        let seen = currentEvent()
        let event = QueuedCommandPolicy.fresh(
            seen,
            after: QueuedCommandPolicy.newest(lastCommandEventTime, eventTimeAtEnd),
        )
        if let seen {
            lastCommandEventTime = max(lastCommandEventTime ?? seen.time, seen.time)
        }
        let age = secondsSincePress()
        let press = QueuedCommandPolicy.pressTime(now: uptime(), secondsSince: age, launch: launchUptime)
        BatchTrace.event("ledger.command.press", value: press ?? -1)
        BatchTrace.event("ledger.command.pressAge", value: age ?? -1)
        let drops = QueuedCommandPolicy.dropsCommand(
            event: event,
            pressTime: press,
            lastBatch: lastBatch,
            lastDroppedEventTime: lastDroppedEventTime,
            lastDroppedPressTime: lastDroppedPressTime,
        )
        // The event's time, to line up with `ledger.batch.start` and `.end`.
        BatchTrace.event(drops ? "ledger.command.dropped" : "ledger.command.passed", value: event?.time ?? -1)
        if drops, let event {
            if event.isMouse {
                lastDroppedPressTime = press
            } else {
                lastDroppedEventTime = event.time
            }
        }
        return drops
    }

    private func refreshHistories() {
        for entry in histories {
            entry.history?.refreshMenu()
        }
    }

    /// A change that may have touched anything: every window reloads.
    func changed() {
        changed(.everything)
    }

    /// One change, with what it touched (N5 on #286). A batch posts one, when it commits. Every observer of
    /// `revision` still hears it; a register whose account it didn't touch skips its reload (`delta(since:)`).
    func changed(_ delta: LedgerDelta) {
        let span = BatchTrace.begin("ledger.notify")
        defer { span.end() }
        bump(delta)
        BatchTrace.event("ledger.notify.post")
        startRefreshes()
        runChangedHandlers()
    }

    /// Starts, and counts, the refresh of every registered account history the change touched, before `changed(_:)`
    /// returns; the view's `onChange` that follows finds it up to date and does nothing more (B2).
    private func startRefreshes() {
        registers.removeAll { $0.model == nil }
        for model in registers.compactMap(\.model) {
            if let revision = model.claimRefresh(after: self) {
                Task { await model.runRefresh(after: self, counted: revision) }
            }
        }
    }

    /// Everything that changed after `seen`, a revision a window has shown: `nothing` when it's up to date, and
    /// `everything` when it's further behind than the kept history.
    public func delta(since seen: Int) -> LedgerDelta {
        guard seen < revision else {
            return .nothing
        }
        guard let oldest = deltas.first?.revision, oldest <= seen + 1 else {
            return .everything
        }
        return deltas.filter { $0.revision > seen }.reduce(.nothing) { $0.merging($1.delta) }
    }

    /// Runs `handler` after every change and every restore, for state kept outside the ledger that follows it, such
    /// as the Scheduled reminders (#26, D340.7). Registered once per launch.
    func onChanged(_ handler: @escaping @MainActor () -> Void) {
        changedHandlers.append(handler)
    }

    private func runChangedHandlers() {
        for handler in changedHandlers {
            handler()
        }
    }

    /// One `onLedgerReplaced` handler, for removing it again.
    struct ReplacedHandler: Hashable {
        fileprivate let id: UUID
    }

    /// Runs `handler` on every restore, before the reload, for state kept beside the ledger, such as the
    /// Scheduled catch-up hint (#26). Something registered per window, rather than once per launch, removes its
    /// handler with the returned token when it goes (Tech Architect NB 3).
    @discardableResult
    func onLedgerReplaced(_ handler: @escaping @MainActor () -> Void) -> ReplacedHandler {
        let token = ReplacedHandler(id: UUID())
        replacedHandlers.append((token.id, handler))
        return token
    }

    /// Stops running a handler from `onLedgerReplaced`. Removing it twice does nothing.
    func removeLedgerReplacedHandler(_ token: ReplacedHandler) {
        replacedHandlers.removeAll { $0.id == token.id }
    }

    func add(_ history: WindowUndoHistory) {
        histories.removeAll { $0.history == nil }
        histories.append(WeakHistory(history: history))
    }

    /// Registers a window's account history, held weakly: each change then starts its refresh (B2). Adding it again
    /// does nothing.
    func add(_ register: AccountHistoryViewModel) {
        remove(register)
        registers.append(WeakRegister(model: register))
    }

    /// Stops starting `register`'s refreshes, as when its view goes. Removing it twice does nothing.
    func remove(_ register: AccountHistoryViewModel) {
        registers.removeAll { $0.model == nil || $0.model === register }
    }

    /// The whole ledger was replaced outside any window, by a backup restore (#40, #99). Every window's
    /// history is cleared, since its steps were made against the old data (D187.2), and every window reloads.
    public func ledgerReplaced() {
        for entry in histories {
            entry.history?.clear()
            // A failed or stale Undo's alert is about a step that's gone now, so it doesn't outlive the old data
            // (Tech Architect N6).
            entry.history?.alert = nil
        }
        for handler in replacedHandlers {
            handler.run()
        }
        bump(.everything)
        runChangedHandlers()
    }

    /// The next revision, with what it touched. Every revision goes through here, so `deltas` has no gaps.
    private func bump(_ delta: LedgerDelta) {
        deltas.append((revision + 1, delta))
        if deltas.count > Self.deltaHistory {
            deltas.removeFirst(deltas.count - Self.deltaHistory)
        }
        revision += 1
    }
}

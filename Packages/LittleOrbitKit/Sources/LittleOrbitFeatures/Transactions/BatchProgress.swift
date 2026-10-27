import Foundation
import LittleOrbitCore
import LittleOrbitDomain
import Observation

/// The progress of a Bulk Edit, or of its Undo or Redo, for the sheet (#285, D398.3): rows checked so far, then
/// "Saving…" with the bar full while the one write runs. While the rows are built, off the main actor, the sheet
/// shows once the work has run for `showDelay`, so a quick one never flashes it. The save blocks the main actor,
/// so that timer can't fire during it: just before the save, `BatchSheetPolicy` decides whether the sheet goes up
/// first, and the save then waits until it has drawn (D401). A store that saves off the main actor (#285, B)
/// leaves the main actor free: then the sheet needn't be drawn first, the timer keeps running through the save,
/// and the bar moves while it runs. The sheet goes up once at most, whichever asks first.
@MainActor
@Observable
public final class BatchProgress {
    public enum Kind: Equatable, Sendable {
        case applying
        case undoing
        case redoing
    }

    public enum Stage: Equatable, Sendable {
        /// Checking the rows, off the main actor.
        case updating
        /// The one write: on the main actor, or off it (`savesOffMain`).
        case saving
    }

    /// How long the work runs before the sheet shows (D398.3).
    public static let showDelay = Duration.milliseconds(500)
    /// About one frame: long enough for the main run loop to go idle, so SwiftUI commits and draws (N5).
    public static let uiTurnLength = Duration.milliseconds(16)

    /// The longest the save waits for a sheet it asked for to appear, so "Saving…" holds the work up only briefly
    /// (D401.4: at most 0.75 s, with `sheetSettle` and a turn).
    public static let sheetAppearLimit = Duration.milliseconds(300)
    /// Once the sheet has appeared, how long it gets to draw and settle before the save blocks the main actor:
    /// about three frames.
    public static let sheetSettle = Duration.milliseconds(50)

    /// Gives the UI a real turn of the main run loop before main-thread work: `Task.yield()` alone resumes in the
    /// same turn, so nothing would draw. The sleep lets the run loop go idle, and SwiftUI commits what changed (N5).
    static func uiTurn() async {
        try? await Task.sleep(for: uiTurnLength)
    }

    public let kind: Kind
    /// The transactions being changed, for the message and the bar.
    public let total: Int
    public private(set) var done = 0
    public private(set) var stage = Stage.updating
    public private(set) var isShown = false
    /// Whether the batch was handed off to a save off the main actor, so the bar moves while it runs (#285, B).
    /// Set at the hand-off (`LedgerBatchReporter.handingOff`), not when "Saving…" starts (D405.5).
    public private(set) var savesOffMain = false
    /// How many times the sheet went up: once at most (#285, B).
    @ObservationIgnored private(set) var timesShown = 0

    /// `showDelay` in the app; `nil` runs no timer, for tests that must never see a timer-shown sheet.
    @ObservationIgnored private let delay: Duration?
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    @ObservationIgnored private var startedAt: ContinuousClock.Instant?
    @ObservationIgnored private var continuation: AsyncStream<Int>.Continuation?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    /// The half-second timer, for the build only: the save cancels it.
    @ObservationIgnored private(set) var timer: Task<Void, Never>?
    /// Set when the sheet's progress view appears.
    @ObservationIgnored private(set) var hasAppeared = false
    /// Whether the sheet's progress view is on screen: it appeared and hasn't disappeared yet.
    @ObservationIgnored private(set) var isOnScreen = false
    /// What VoiceOver hears once the sheet has closed, and how it's posted (Tester2 on c8c6594).
    @ObservationIgnored private var pendingAnnouncement: (text: String, post: @MainActor (String) -> Void)?
    /// Posts a held announcement if the sheet never reports that it closed.
    @ObservationIgnored private var announcementFallback: Task<Void, Never>?
    /// Set once the sheet has closed.
    @ObservationIgnored private(set) var sheetHasClosed = false

    /// How long a held announcement waits for the sheet to close before it's posted anyway, counted from the
    /// first free turn of the main actor after the batch ended, when SwiftUI starts the dismissal.
    static let announcementFallbackDelay = Duration.milliseconds(1_500)
    /// The safety limit: while the sheet's view is still on screen the wait goes on, up to this long in all, so a
    /// sheet that never closes still gets its announcement.
    static let announcementFallbackLimit = Duration.seconds(5)
    /// How often a wait past `announcementFallbackDelay` checks whether the sheet's view has gone.
    static let announcementFallbackRecheck = Duration.milliseconds(100)
    /// `announcementFallbackDelay` and `announcementFallbackLimit`; tests shorten them.
    @ObservationIgnored var fallbackDelay = BatchProgress.announcementFallbackDelay
    @ObservationIgnored var fallbackLimit = BatchProgress.announcementFallbackLimit
    /// Once the sheet's `onDismiss` ran, how long after the main actor's next free turn the held announcement
    /// waits for the dismissal to finish and focus to go back to the window (Tester2 on 8728d1f: the sheet went
    /// 0.01 s after that turn, focus 0.05–0.12 s after).
    static let dismissSettle = Duration.milliseconds(150)
    /// How the announcement's waits sleep: `Task.sleep` in the app; tests step it by hand, so no wait depends on
    /// real time under load.
    @ObservationIgnored var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    /// The wait after `sheetDismissed()`.
    @ObservationIgnored private var dismissWait: Task<Void, Never>?

    init(
        kind: Kind,
        total: Int,
        showAfter delay: Duration? = BatchProgress.showDelay,
        now: @escaping () -> ContinuousClock.Instant = { .now },
    ) {
        self.kind = kind
        self.total = max(total, 0)
        self.delay = delay
        self.now = now
    }

    /// Whether the bar is the indeterminate "Saving…" one (#285, B; UI Designer's approval; D405.5): only once the
    /// batch is handed off to the save off the main actor. While the rows are checked and "Saving…" starts, it's
    /// determinate. It switches once and never back: `stage` doesn't leave `.saving` and `savesOffMain` is never
    /// cleared, so a late row count or a save that falls back to the main actor keeps it.
    public var showsIndeterminateBar: Bool {
        stage == .saving && savesOffMain
    }

    /// The bar's value, from 0 to `total`; full while saving.
    public var value: Double {
        Double(stage == .saving ? total : min(done, total))
    }

    /// Starts the clock for the sheet and returns what the batch reports to. Rows reported off the main actor
    /// arrive here through an `AsyncStream`.
    func start() -> LedgerBatchReporter {
        let (stream, continuation) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        tasks.append(
            Task { [weak self] in
                for await done in stream {
                    self?.rowsDone(done)
                }
            }
        )
        startedAt = now()
        if let delay {
            timer = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, !self.isShown else {
                    return
                }
                self.show()
                BatchTrace.event("batch.sheet.shown", "timer")
            }
        }
        return LedgerBatchReporter(
            rowsDone: { continuation.yield($0) },
            willSave: { [weak self] rows in await self?.willSave(changing: rows) },
            willSaveOffMain: { [weak self] rows in await self?.willSaveOffMain(changing: rows) },
            handingOff: { [weak self] in self?.handedOff() },
        )
    }

    /// The sheet's progress view appeared: a save waiting for it can start once it has drawn.
    public func sheetAppeared() {
        hasAppeared = true
        isOnScreen = true
    }

    /// The sheet's progress view went away. A held announcement still waits for `sheetClosed()`; this only lets
    /// the fallback know the sheet isn't drawn any more.
    public func sheetDisappeared() {
        isOnScreen = false
    }

    /// Posts `text`, how a batch ended, after its sheet has closed, so VoiceOver hears it over the window and not
    /// over a sheet that's going away (Tester2 on c8c6594). With no sheet, or one already closed, it's posted now.
    /// If the sheet never reports closing, it's posted all the same: `announcementFallbackDelay` after the
    /// dismissal starts, later while the sheet's view is still on screen, and by `announcementFallbackLimit` at
    /// the latest. The wait starts at the main actor's first free turn, not when the batch ended: a long main
    /// block after the batch holds the dismissal up too, and the fallback mustn't run out during it (k1, Undo run 4
    /// on c6b3778: announced at +1.41 s, sheet closed at +1.88 s).
    func announceAfterSheet(_ text: String, post: @escaping @MainActor (String) -> Void) {
        guard isShown, !sheetHasClosed else {
            post(text)
            return
        }
        pendingAnnouncement = (text, post)
        announcementFallback = Task { [self] in
            await sleep(Self.uiTurnLength)
            BatchTrace.event("batch.sheet.dismissRequested")
            await sleep(fallbackDelay)
            var waited = fallbackDelay
            while isOnScreen, waited < fallbackLimit, !Task.isCancelled {
                await sleep(Self.announcementFallbackRecheck)
                waited += Self.announcementFallbackRecheck
            }
            guard !Task.isCancelled, pendingAnnouncement != nil else {
                return
            }
            BatchTrace.event("batch.announce.fallback", isOnScreen ? "limit" : "notDrawn")
            postPendingAnnouncement()
        }
    }

    /// The sheet has closed: a held announcement is posted now. Bulk Edit calls it when its own sheet's view has
    /// gone, at the end of the sheet's close.
    public func sheetClosed() {
        sheetHasClosed = true
        announcementFallback?.cancel()
        announcementFallback = nil
        dismissWait?.cancel()
        dismissWait = nil
        postPendingAnnouncement()
    }

    /// The Undo or Redo sheet's `onDismiss` ran. On macOS it can run as the dismissal starts, and the main actor can
    /// then stay busy, with the sheet still up, while the register updates (Tester2 on 8728d1f: announced 0.40–0.50 s
    /// before the dismissal, 10 of 10). So a held announcement waits for the main actor's next free turn, when the
    /// dismissal goes ahead, then `dismissSettle` for it to finish, and is posted then, once. The fallback stops.
    public func sheetDismissed() {
        guard !sheetHasClosed else {
            return
        }
        sheetHasClosed = true
        announcementFallback?.cancel()
        announcementFallback = nil
        guard pendingAnnouncement != nil else {
            return
        }
        BatchTrace.event("batch.sheet.onDismiss")
        dismissWait = Task { [self] in
            // The value is how long past one turn this waited: the main actor busy with the dismissal, not idle.
            let clock = ContinuousClock()
            let asked = clock.now
            await sleep(Self.uiTurnLength)
            BatchTrace.event("batch.sheet.dismissTurn", value: Self.seconds(clock.now - asked - Self.uiTurnLength))
            let idle = BatchTrace.begin("batch.sheet.dismissIdle")
            await sleep(Self.dismissSettle)
            idle.end()
            guard !Task.isCancelled else {
                return
            }
            BatchTrace.event("batch.announce.afterDismiss")
            postPendingAnnouncement()
        }
    }

    /// Returns once the sheet has gone, when a held announcement would be posted (`announceAfterSheet`): at once with
    /// no sheet, or one already closed; otherwise after `sheetDismissed()` and `dismissSettle`, after `sheetClosed()`,
    /// or by the fallback. A batch Undo or Redo posts its change, so the windows refresh, only then (D405 on 1f2eae8).
    func sheetHasGone() async {
        await withCheckedContinuation { continuation in
            announceAfterSheet("") { _ in continuation.resume() }
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func postPendingAnnouncement() {
        guard let pending = pendingAnnouncement else {
            return
        }
        pendingAnnouncement = nil
        pending.post(pending.text)
    }

    /// Stops following the batch. The sheet goes with the model.
    func finish() {
        continuation?.finish()
        continuation = nil
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
        cancelTimer()
    }

    /// Puts the sheet up, unless it's up already.
    private func show() {
        guard !isShown else {
            return
        }
        isShown = true
        timesShown += 1
        // The first free turn of the main actor once the sheet is asked for: with `batch.sheet.shown`, it brackets
        // the main-thread time the sheet's presentation takes (D405, Tester2 on 1f2eae8).
        Task {
            await Self.uiTurn()
            BatchTrace.event("batch.sheet.mainFree")
        }
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    private func rowsDone(_ count: Int) {
        guard stage == .updating else {
            return
        }
        done = min(count, total)
    }

    /// "Saving…" with the bar full. The timer stops, since it can't fire during the save. The sheet goes up now
    /// if `BatchSheetPolicy` says so, and the save waits until it has drawn; otherwise the UI still gets a turn of
    /// the run loop, so it's up to date before the write blocks the main actor (N5, D401). With no row to change,
    /// there's no sheet at all, and one already up closes (D402).
    private func willSave(changing rows: Int) async {
        cancelTimer()
        done = total
        stage = .saving
        let elapsed = startedAt.map { now() - $0 } ?? .zero
        switch BatchSheetPolicy.beforeSave(elapsed: elapsed, changedRows: rows, isShown: isShown) {
        case .keepShown, .skip:
            await Self.uiTurn()
        case .show:
            show()
            await waitForSheet()
        case .none:
            // Nothing will be written: an Apply that changes no row never shows the sheet (D402).
            isShown = false
        }
    }

    /// "Saving…" for a save off the main actor (#285, B), which leaves the main actor free: the sheet goes up now
    /// if `BatchSheetPolicy` says so, without waiting for it to draw, and the half-second timer keeps running, so a
    /// save that runs long still shows it. Both run on the main actor and check `isShown`, so it goes up once. With
    /// no row to change, there's no sheet at all (D402). It returns without a turn of the run loop: the batch is
    /// handed off at once, and the sheet is presented and drawn while the save runs, instead of before it (Tester2
    /// on 8728d1f: Undo and Redo spent about 0.35 s on main between the sheet going up and the hand-off).
    private func willSaveOffMain(changing rows: Int) async {
        done = total
        stage = .saving
        let elapsed = startedAt.map { now() - $0 } ?? .zero
        switch BatchSheetPolicy.beforeSave(elapsed: elapsed, changedRows: rows, isShown: isShown) {
        case .keepShown, .skip:
            break
        case .show:
            show()
            BatchTrace.event("batch.sheet.shown", "beforeSave")
        case .none:
            cancelTimer()
            isShown = false
        }
    }

    /// The batch is being handed off to the save off the main actor: the bar turns indeterminate now, once (D405.5).
    private func handedOff() {
        guard stage == .saving else {
            return
        }
        savesOffMain = true
    }

    /// Turns of the run loop until the sheet's view appears, for `sheetAppearLimit` at most, then `sheetSettle`
    /// for it to draw. The signpost says whether it appeared in time.
    private func waitForSheet() async {
        // The real clock, not `now`, which tests may stop: the wait must always end.
        let clock = ContinuousClock()
        let asked = clock.now
        while !hasAppeared, clock.now - asked < Self.sheetAppearLimit, !Task.isCancelled {
            await Self.uiTurn()
        }
        if hasAppeared {
            try? await Task.sleep(for: Self.sheetSettle)
            BatchTrace.event("batch.sheet.shown", "beforeSave")
        } else {
            BatchTrace.event("batch.sheet.shown", "beforeSaveTimedOut")
        }
    }
}

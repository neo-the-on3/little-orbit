import Foundation
import LittleOrbitCore
import LittleOrbitDomain
import Observation

/// The progress of a Bulk Edit, or of its Undo or Redo, for the sheet (#285, D398.3): rows checked so far, then
/// "Saving…" with the bar full while the one write runs. While the rows are built, off the main actor, the sheet
/// shows once the work has run for `showDelay`, so a quick one never flashes it. The save blocks the main actor,
/// so that timer can't fire during it: just before the save, `BatchSheetPolicy` decides whether the sheet goes up
/// first, and the save then waits until it has drawn (D401).
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
        /// The one write, on the main actor.
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

    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    @ObservationIgnored private var startedAt: ContinuousClock.Instant?
    @ObservationIgnored private var continuation: AsyncStream<Int>.Continuation?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    /// The half-second timer, for the build only: the save cancels it.
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// Set when the sheet's progress view appears.
    @ObservationIgnored private(set) var hasAppeared = false
    /// What VoiceOver hears once the sheet has closed, and how it's posted (Tester2 on c8c6594).
    @ObservationIgnored private var pendingAnnouncement: (text: String, post: @MainActor (String) -> Void)?
    /// Posts a held announcement if the sheet never reports that it closed.
    @ObservationIgnored private var announcementFallback: Task<Void, Never>?
    /// Set once the sheet has closed.
    @ObservationIgnored private(set) var sheetHasClosed = false

    /// How long a held announcement waits for the sheet to close before it's posted anyway.
    static let announcementFallbackDelay = Duration.milliseconds(1_500)

    init(
        kind: Kind,
        total: Int,
        showAfter delay: Duration = BatchProgress.showDelay,
        now: @escaping () -> ContinuousClock.Instant = { .now },
    ) {
        self.kind = kind
        self.total = max(total, 0)
        self.delay = delay
        self.now = now
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
        timer = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.isShown else {
                return
            }
            self.isShown = true
            BatchTrace.event("batch.sheet.shown", "timer")
        }
        return LedgerBatchReporter(
            rowsDone: { continuation.yield($0) },
            willSave: { [weak self] rows in await self?.willSave(changing: rows) },
        )
    }

    /// The sheet's progress view appeared: a save waiting for it can start once it has drawn.
    public func sheetAppeared() {
        hasAppeared = true
    }

    /// Posts `text`, how a batch ended, after its sheet has closed, so VoiceOver hears it over the window and not
    /// over a sheet that's going away (Tester2 on c8c6594). With no sheet, or one already closed, it's posted now.
    /// If the sheet never reports closing, it's posted after `announcementFallbackDelay` all the same.
    func announceAfterSheet(_ text: String, post: @escaping @MainActor (String) -> Void) {
        guard isShown, !sheetHasClosed else {
            post(text)
            return
        }
        pendingAnnouncement = (text, post)
        announcementFallback = Task { [self] in
            try? await Task.sleep(for: Self.announcementFallbackDelay)
            guard !Task.isCancelled else {
                return
            }
            postPendingAnnouncement()
        }
    }

    /// The sheet has closed: a held announcement is posted now.
    public func sheetClosed() {
        sheetHasClosed = true
        announcementFallback?.cancel()
        announcementFallback = nil
        postPendingAnnouncement()
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
            isShown = true
            await waitForSheet()
        case .none:
            // Nothing will be written: an Apply that changes no row never shows the sheet (D402).
            isShown = false
        }
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

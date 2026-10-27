import Foundation
import LittleOrbitCore
import LittleOrbitDomain
import Observation

/// The progress of a Bulk Edit, or of its Undo or Redo, for the sheet (#285, D398.3): rows checked so far, then
/// "Saving…" with the bar full while the one write runs. The sheet shows only once the work has run for
/// `showDelay`, so a quick one never flashes it.
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

    public let kind: Kind
    /// The transactions being changed, for the message and the bar.
    public let total: Int
    public private(set) var done = 0
    public private(set) var stage = Stage.updating
    public private(set) var isShown = false

    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private var continuation: AsyncStream<Int>.Continuation?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(kind: Kind, total: Int, showAfter delay: Duration = BatchProgress.showDelay) {
        self.kind = kind
        self.total = max(total, 0)
        self.delay = delay
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
        tasks.append(
            Task { [weak self, delay] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else {
                    return
                }
                self?.isShown = true
                BatchTrace.event("batch.sheet.shown")
            }
        )
        return LedgerBatchReporter(
            rowsDone: { continuation.yield($0) },
            willSave: { [weak self] in await self?.willSave() },
        )
    }

    /// Stops following the batch. The sheet goes with the model.
    func finish() {
        continuation?.finish()
        continuation = nil
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
    }

    private func rowsDone(_ count: Int) {
        guard stage == .updating else {
            return
        }
        done = min(count, total)
    }

    /// "Saving…" with the bar full. If the sheet is showing, the main actor yields for a moment so it draws
    /// before the write blocks it.
    private func willSave() async {
        done = total
        stage = .saving
        if isShown {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

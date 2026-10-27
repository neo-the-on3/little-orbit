import Foundation

@testable import LittleOrbitFeatures

/// Stands in for `BatchProgress.sleep`: each sleep waits until the test resumes it, so a wait never depends on real
/// time under a loaded parallel run (Tester2 on 8728d1f: `BatchAnnouncementFallbackTests` failed 6 of 6 full runs).
/// A cancelled sleep ends at once, as `Task.sleep` does. Once released (`release()`), every sleep ends at once, so a test
/// that fails early lets what it held run to its end instead of leaving it waiting for good (Tech Architect's m10).
@MainActor
final class ManualSleeper {
    private struct Request {
        let id: UUID
        let duration: Duration
        let continuation: CheckedContinuation<Void, Never>
    }

    private var requests: [Request] = []
    /// Every duration asked for, in order, resumed or not.
    private(set) var asked: [Duration] = []
    /// The durations held until resumed; any other sleeps in real time. `nil` holds every one.
    private let held: [Duration]?
    /// Set by `release()`.
    private(set) var isReleased = false

    /// `held`: only these durations wait for the test, such as a safety cap or a fallback, so a main actor held up
    /// beside the test can't let them run out before what they guard against; any other sleeps in real time. `nil`,
    /// the default: every one waits.
    init(holding held: [Duration]? = nil) {
        self.held = held
    }

    var sleep: @MainActor (Duration) async -> Void {
        { [self] duration in await self.wait(duration) }
    }

    private func wait(_ duration: Duration) async {
        if let held, !held.contains(duration) {
            try? await Task.sleep(for: duration)
            return
        }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || isReleased {
                    continuation.resume()
                    return
                }
                asked.append(duration)
                requests.append(Request(id: id, duration: duration, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor in self.resume(id) }
        }
    }

    private func resume(_ id: UUID) {
        guard let index = requests.firstIndex(where: { $0.id == id }) else {
            return
        }
        requests.remove(at: index).continuation.resume()
    }

    /// Whether a sleep is waiting now.
    var isWaiting: Bool { !requests.isEmpty }
    /// The sleeps waiting now, oldest first.
    var waiting: [Duration] { requests.map(\.duration) }

    /// Waits until a sleep is asked for, for at most `turns` turns, and returns its duration without ending it;
    /// `nil` if none was asked for, so a test that expects one fails instead of hanging.
    func next(turns: Int = 10_000) async -> Duration? {
        await Self.until(turns: turns) { !requests.isEmpty }
        return requests.first?.duration
    }

    /// Ends the oldest waiting sleep, once one is asked for, and returns its duration; `nil` if none was.
    @discardableResult
    func advance() async -> Duration? {
        guard let duration = await next() else {
            return nil
        }
        requests.removeFirst().continuation.resume()
        return duration
    }

    /// Yields until `done` holds, at most `turns` times: counted turns, not real time.
    static func until(turns: Int = 10_000, _ done: () -> Bool) async {
        var left = turns
        while !done(), left > 0 {
            left -= 1
            await Task.yield()
        }
    }

    /// Ends every waiting sleep, and makes every later one end at once. Tests call it on the way out, in a `defer`,
    /// so a regression that leaves a wait unresumed fails at the `#require` before it rather than hanging the run.
    func release() {
        isReleased = true
        let waiting = requests
        requests.removeAll()
        for request in waiting {
            request.continuation.resume()
        }
    }
}

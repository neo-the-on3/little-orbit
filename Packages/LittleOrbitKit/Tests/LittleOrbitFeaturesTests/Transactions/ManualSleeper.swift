import Foundation

@testable import LittleOrbitFeatures

/// Stands in for `BatchProgress.sleep`: each sleep waits until the test resumes it, so a wait never depends on real
/// time under a loaded parallel run (Tester2 on 8728d1f: `BatchAnnouncementFallbackTests` failed 6 of 6 full runs).
/// A cancelled sleep ends at once, as `Task.sleep` does.
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

    var sleep: @MainActor (Duration) async -> Void {
        { [self] duration in await self.wait(duration) }
    }

    private func wait(_ duration: Duration) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
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

    /// A sleep in real time, except that `held` durations, such as a safety cap or a fallback, last until they're
    /// cancelled: a main actor held up beside the test can't let them run out before what they guard against.
    static func holding(_ held: [Duration]) -> @MainActor (Duration) async -> Void {
        { duration in
            try? await Task.sleep(for: held.contains(duration) ? .seconds(86_400) : duration)
        }
    }
}

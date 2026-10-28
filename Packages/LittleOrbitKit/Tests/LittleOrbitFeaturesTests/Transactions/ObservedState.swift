import Observation
import Synchronization

/// Waits for an `@Observable` model's state rather than for a stretch of real time (#303): `until` returns once
/// `condition` holds, waking only when something it reads changes, so a main actor held up by other suites only
/// makes it later, never wrong. There's no deadline: the suite's time limit stops a regression that never gets
/// there, and cancelling the test ends the wait.
@MainActor
enum ObservedState {
    static func until(_ condition: () -> Bool) async {
        while !condition(), !Task.isCancelled {
            let waiter = Waiter()
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    waiter.set(continuation)
                    withObservationTracking {
                        _ = condition()
                    } onChange: {
                        waiter.resume()
                    }
                    if Task.isCancelled {
                        waiter.resume()
                    }
                }
            } onCancel: {
                waiter.resume()
            }
        }
    }

    /// Resumes its continuation once, whichever of a change or a cancellation comes first.
    private final class Waiter: Sendable {
        private let continuation = Mutex<CheckedContinuation<Void, Never>?>(nil)

        func set(_ next: CheckedContinuation<Void, Never>) {
            continuation.withLock { $0 = next }
        }

        func resume() {
            continuation.withLock { $0.take() }?.resume()
        }
    }
}

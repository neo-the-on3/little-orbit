import Foundation

/// Waits on the main queue, 5 ms at a time and for at most 10 seconds, until `condition` holds.
///
/// The fake writers hold a thread of the shared pool while a test checks what happens meanwhile. `Task.sleep`
/// wakes through that pool, so with every thread held, a test sleeping in its wait would never wake to release
/// them. Each pause here is resumed by the main queue instead, which needs no thread of the pool.
@MainActor
func pollOnMainQueue(until condition: () -> Bool) async {
    for _ in 0..<2_000 where !condition() {
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(5)) { resume.resume() }
        }
    }
}

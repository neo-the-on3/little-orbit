import Foundation

/// Waits on the main queue, 5 ms at a time and for at most 10 seconds, until `condition` holds.
///
/// The fake writers hold a thread while a test checks what happens meanwhile. They hold one of the backups' own
/// work queue now, not the shared pool, but `Task.sleep` wakes through that pool, so the wait keeps off it anyway:
/// each pause here is resumed by the main queue, which needs no thread of the pool.
@MainActor
func pollOnMainQueue(until condition: () -> Bool) async {
    for _ in 0..<2_000 where !condition() {
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(5)) { resume.resume() }
        }
    }
}

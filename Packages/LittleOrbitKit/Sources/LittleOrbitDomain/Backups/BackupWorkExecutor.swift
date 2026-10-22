import Dispatch

/// Where the backups' blocking work runs: reading, hashing, archiving and deleting files, which waits on the disk
/// for as long as the disk takes. It runs on a dispatch queue of its own, not on Swift's shared cooperative pool.
/// That pool has one thread per core, three on CI's runner, and expects every job on it to return promptly; work
/// that blocks there holds a thread nothing else can use meanwhile, so with every thread held no task can resume,
/// including the one that would let the work finish. That's how the macOS test run hung on 34b280a. This queue's
/// threads are the system's to add when one blocks, so a slow disk, or a test fake holding a write, never stops
/// the rest of the app's tasks.
///
/// The work still runs in a task, so cancelling it and checking for that between chunks work as before.
final class BackupWorkExecutor: TaskExecutor {
    static let shared = BackupWorkExecutor()

    private let queue = DispatchQueue(label: "LittleOrbit.backup-work", attributes: .concurrent)

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedTaskExecutor()
        queue.async(qos: Self.qos(job.priority)) {
            job.runSynchronously(on: executor)
        }
    }

    /// The dispatch QoS for a task's priority, so a user-initiated backup isn't run as background work.
    private static func qos(_ priority: JobPriority) -> DispatchQoS {
        switch priority.rawValue {
        case TaskPriority.userInitiated.rawValue...:
            .userInitiated
        case TaskPriority.medium.rawValue...:
            .default
        case TaskPriority.utility.rawValue...:
            .utility
        default:
            .background
        }
    }
}

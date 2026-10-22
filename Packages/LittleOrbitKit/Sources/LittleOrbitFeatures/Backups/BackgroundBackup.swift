import Foundation

/// One background-time assertion's ID, as the platform gave it.
public struct BackgroundActivityID: Hashable, Sendable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// Time to finish work after the app goes to the background. The iOS App target implements it over
/// `UIApplication.beginBackgroundTask`, so Domain and Features stay UIKit-free; macOS doesn't need one.
@MainActor
public protocol BackgroundActivity: AnyObject {
    /// Asks for time to finish `name`. `expired` runs on the main actor if the time runs out first; the activity is
    /// ended right after it. `nil` when the system gives no time.
    func begin(_ name: String, expired: @escaping @MainActor () -> Void) -> BackgroundActivityID?
    /// Says the work is done. Called once for each ID `begin` returned.
    func end(_ id: BackgroundActivityID)
}

/// The automatic backup when the app goes to the background, inside one background-time assertion. If the time
/// runs out, the backup task is cancelled and the assertion ended at once. The backup then stops between chunks:
/// its unfinished folder is removed from the staging folder, or by the launch sweep if the app is suspended first,
/// and nothing is pruned.
@MainActor
final class BackgroundBackupRun {
    static let name = "Automatic backup"

    private let activity: (any BackgroundActivity)?
    private var id: BackgroundActivityID?
    private(set) var task: Task<Void, Never>?

    init(activity: (any BackgroundActivity)?) {
        self.activity = activity
    }

    func start(_ work: @escaping @MainActor () async -> Void, finished: @escaping @MainActor () -> Void) {
        id = activity?
            .begin(Self.name) { [weak self] in
                self?.expire()
            }
        task = Task { [weak self] in
            await work()
            self?.end()
            finished()
        }
    }

    private func expire() {
        task?.cancel()
        end()
    }

    private func end() {
        if let id {
            self.id = nil
            activity?.end(id)
        }
    }
}

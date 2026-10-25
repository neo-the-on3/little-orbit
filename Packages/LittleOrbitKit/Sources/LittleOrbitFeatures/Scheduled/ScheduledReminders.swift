import Foundation
import LittleOrbitDomain

/// Keeps the pending reminders current (D340.7), once per launch for every window. Each `refresh()` asks for a
/// reschedule; one that arrives while another runs makes it run once more afterwards, so two never overlap and the
/// last change always wins.
@MainActor
public final class ScheduledReminders {
    private let useCase: any ScheduleRemindersUseCase
    /// Called when a reschedule failed; the App logs it with no user data. Each error domain and code is passed on
    /// once per launch, so a refusal that repeats on every change isn't logged each time (Tech Architect NB2).
    private let onProblem: (any Error) -> Void
    private var reported: Set<String> = []
    private var running: Task<Void, Never>?
    private var again = false

    public init(useCase: any ScheduleRemindersUseCase, onProblem: @escaping (any Error) -> Void = { _ in }) {
        self.useCase = useCase
        self.onProblem = onProblem
    }

    /// Reschedules soon. The returned task finishes when every reschedule asked for so far has run.
    @discardableResult
    public func refresh() -> Task<Void, Never> {
        if let running {
            again = true
            return running
        }
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await run()
        }
        running = task
        return task
    }

    /// The reschedule running now, if any, for tests to wait on.
    var inFlight: Task<Void, Never>? {
        running
    }

    private func run() async {
        repeat {
            again = false
            do {
                try await useCase.reschedule()
            } catch {
                let code = error as NSError
                if reported.insert("\(code.domain) \(code.code)").inserted {
                    onProblem(error)
                }
            }
        } while again
        running = nil
    }
}

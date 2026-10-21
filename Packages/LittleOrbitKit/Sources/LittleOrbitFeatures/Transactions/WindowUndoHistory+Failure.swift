import Foundation
import LittleOrbitDomain

// MARK: A failed Undo or Redo (X8, X8a, X8b; D191.3, D193)
//
// A failed Undo or Redo writes nothing, and the step goes back on the list it came from, so the same command
// works once the write succeeds; every other step stays where it was. The `UndoManager` has already taken the
// step off its list when the handler runs, and while a handler runs, anything it registers lands on the other
// list (registering after it returns would clear Redo). So the handler registers a stand-in there, and once the
// Undo or Redo has returned, the history redoes (or undoes) the stand-in, which registers the step again where
// it was.
//
// From the failure until its alert is dismissed, the history is blocked: every Undo or Redo of one of its steps,
// from Cmd-Z, the Edit menu, shake or a queued key press, applies nothing and goes back the same way. If such a
// command comes before the failed step is back, the failed step is dropped, and the alert says so (X8b).

/// The state of a failure and of the stand-ins it left on the `UndoManager`.
struct UndoFailureBlock {
    /// From a failure until its alert is dismissed.
    var isBlocked = false
    /// The failure alert's message, before any added line.
    var message = ""
    /// Stand-ins on the `UndoManager`, oldest first.
    var standIns: [UndoStandIn] = []
    /// A step or stand-in handler ran since the last Undo or Redo notification.
    var handlerRan = false
    /// Something other than this history used the `UndoManager` while blocked, such as typing in a field.
    var overtaken = false
    /// The history itself is putting steps back.
    var finishing = false
    var finishScheduled = false
    /// The alert was dismissed while stand-ins were still waiting: the block ends when they are finished.
    var isDismissed = false
}

/// Holds a step's place on the other list of the `UndoManager` until it is put back where it was.
@MainActor
final class UndoStandIn {
    let step: WindowUndoHistory.Step
    let title: String
    /// The step goes back on Undo (it was taken off by an Undo), or on Redo.
    let backOnUndo: Bool
    /// The step whose Undo or Redo failed, rather than one swallowed after it.
    let isFailedStep: Bool
    /// Given up: when the `UndoManager` runs it, it registers itself again on the other list, so no empty group
    /// is left behind, until the history removes it.
    var isDropped = false
    /// Ran, so the step is back.
    var hasRun = false

    init(step: WindowUndoHistory.Step, title: String, backOnUndo: Bool, isFailedStep: Bool) {
        self.step = step
        self.title = title
        self.backOnUndo = backOnUndo
        self.isFailedStep = isFailedStep
    }
}

extension WindowUndoHistory {
    /// The step's Undo or Redo failed: "Couldn't Make the Change", and the history blocks until it's dismissed.
    func fail(_ step: Step, undoing: Bool, title: String, error: any Error) {
        failure.isBlocked = true
        failure.message = AccountHistoryViewModel.message(for: error)
        alert = UndoAlert(title: Self.failedTitle, message: failure.message)
        addStandIn(for: step, backOnUndo: undoing, title: title, isFailedStep: true)
        refreshMenu()
    }

    /// A command while blocked applies nothing, and its step goes back where it was. A failed step that isn't
    /// back yet is dropped instead, because another command came first (X8b).
    func swallow(_ step: Step, undoing: Bool, title: String) {
        for standIn in failure.standIns where standIn.isFailedStep && !standIn.hasRun && !standIn.isDropped {
            discard(standIn)
        }
        addStandIn(for: step, backOnUndo: undoing, title: title, isFailedStep: false)
        refreshMenu()
    }

    /// A new step or a cleared history: any stand-ins go, with the steps they hold, and the block ends.
    func endFailure() {
        for standIn in failure.standIns {
            standIn.isDropped = true
            registrar?.removeSteps(for: standIn)
        }
        failure = UndoFailureBlock()
    }

    /// Follows the `UndoManager` while blocked, then updates the menu state.
    func managerChanged(_ event: UndoEvent) {
        if failure.isBlocked, !failure.finishing, let registrar {
            switch event {
            case .undid, .redid:
                // An Undo or Redo that none of this history's handlers ran, such as a field's typing.
                if !failure.handlerRan {
                    failure.overtaken = true
                }
            case .openedGroup:
                if !registrar.isUndoing, !registrar.isRedoing {
                    failure.overtaken = true
                }
            case .closedGroup:
                break
            }
        }
        if event == .undid || event == .redid {
            failure.handlerRan = false
        }
        refreshMenu()
    }

    private func addStandIn(for step: Step, backOnUndo: Bool, title: String, isFailedStep: Bool) {
        let standIn = UndoStandIn(step: step, title: title, backOnUndo: backOnUndo, isFailedStep: isFailedStep)
        register(standIn)
        failure.standIns.append(standIn)
        if !failure.finishScheduled {
            failure.finishScheduled = true
            later { [weak self] in self?.finishStandIns() }
        }
    }

    private func register(_ standIn: UndoStandIn) {
        registrar?
            .registerStep(standIn, named: standIn.title) { [weak self, weak standIn] in
                guard let self, let standIn else {
                    return
                }
                self.failure.handlerRan = true
                if standIn.isDropped {
                    self.register(standIn)
                    return
                }
                // Whoever runs it, the history or a queued command, it only puts the step back.
                standIn.hasRun = true
                if standIn.backOnUndo {
                    self.undoSteps.append(standIn.step)
                } else {
                    self.redoSteps.append(standIn.step)
                }
                self.register(standIn.step, as: standIn.title)
            }
    }

    /// Once the Undo or Redo has returned: dropped stand-ins are removed, then each other one, newest first, is
    /// redone (or undone), which puts its step back. That runs only while the stand-ins are surely the newest
    /// items on their lists: nothing else used the `UndoManager`, no group is open, and it isn't undoing or
    /// redoing. Otherwise they are all dropped, with the steps they hold; nothing is written either way.
    private func finishStandIns() {
        failure.finishScheduled = false
        defer { endBlockIfFinished() }
        guard let registrar else {
            failure.standIns.removeAll()
            return
        }
        failure.finishing = true
        defer { failure.finishing = false }
        let safe =
            !failure.overtaken && registrar.groupingLevel == 0 && !registrar.isUndoing
            && !registrar.isRedoing
        if !safe {
            for standIn in failure.standIns where !standIn.hasRun {
                discard(standIn)
            }
        }
        // Outside an Undo or Redo, removing them leaves no empty group.
        for standIn in failure.standIns where standIn.isDropped || standIn.hasRun {
            registrar.removeSteps(for: standIn)
        }
        failure.standIns.removeAll { $0.isDropped || $0.hasRun }
        while let standIn = failure.standIns.popLast() {
            if standIn.backOnUndo {
                registrar.redo()
            } else {
                registrar.undo()
            }
            registrar.removeSteps(for: standIn)
            guard standIn.hasRun else {
                // Something else was newest after all: stop rather than redo or undo more.
                for rest in failure.standIns + [standIn] {
                    discard(rest)
                    registrar.removeSteps(for: rest)
                }
                failure.standIns.removeAll()
                break
            }
        }
        failure.overtaken = false
        refreshMenu()
    }

    /// After the alert is dismissed, the block ends once no stand-in is waiting for the deferred work.
    func endBlockIfFinished() {
        guard failure.isBlocked, failure.isDismissed, !failure.finishScheduled, failure.standIns.isEmpty else {
            return
        }
        failure.isBlocked = false
        failure.isDismissed = false
        refreshMenu()
    }

    /// Gives up a stand-in, and the step it holds; the alert says the change was removed (X8b). Once the alert
    /// was dismissed, it isn't shown again.
    private func discard(_ standIn: UndoStandIn) {
        standIn.isDropped = true
        if failure.isBlocked, !failure.isDismissed {
            alert = UndoAlert(
                title: Self.failedTitle,
                message: failure.message + "\n" + UndoText.removedFromHistory,
            )
        }
    }
}

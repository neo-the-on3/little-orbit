import Foundation
import LittleOrbitDomain
import Observation

/// One window's undo history (D187.2): the changes made in this window, from any of its accounts, screens,
/// sheets and alerts. Each window has its own; closing the window discards it, and a new or restored window
/// starts empty (D187.8). The data stays in the one shared store.
///
/// Each step is registered on the window's own `UndoManager`, so the Edit menu, Cmd-Z, shake and the iPad
/// shortcut overlay act on it as the system does. The toolbar Undo and Redo and the toast's Undo go through
/// that `UndoManager` too. Names say exactly what will change, with a count and where it happened (D161,
/// D166, D198); the toast and the notice say where only when it isn't on this window's screen (D165, D187.3).
///
/// Another window, or something outside any window, may change a step's records first. Each step keeps what
/// its change left, and Undo or Redo checks that first (D187.5): a stale step changes nothing, says why and
/// is removed; a failure such as a full disk changes nothing and keeps the step, and every other step, where
/// it was, to try again (X8, X8a, D191.3).
@MainActor
@Observable
public final class WindowUndoHistory {
    /// What this window shows, for the names and the notice.
    public private(set) var screen: UndoScreen = .list(visible: [])
    public private(set) var toast: UndoToast?
    public private(set) var notice: UndoNotice?
    public internal(set) var alert: UndoAlert?
    /// What the toolbar's Undo and Redo show, as the Edit menu does. Kept here and updated only from the
    /// window's `UndoManager` notifications and this history's own steps, never read from the `UndoManager`
    /// while a view draws (Tester's B1 on #87).
    public private(set) var canUndo = false
    public private(set) var canRedo = false
    /// What Undo would reverse, as the Edit menu shows it; `nil` when there is nothing.
    public private(set) var undoTitle: String?
    /// What Redo would repeat: the user's action, not its inverse.
    public private(set) var redoTitle: String?

    /// This window's steps on its `UndoManager`, oldest first. They are the `UndoManager`'s targets and are
    /// kept only to find a step again: for the toast, the account delete and a rename.
    var undoSteps: [Step] = []
    var redoSteps: [Step] = []

    @ObservationIgnored weak var registrar: (any UndoRegistrar)?
    /// Keeps the `UndoManager` notifications coming while this history is attached.
    @ObservationIgnored private var observation: AnyObject?
    /// A failed Undo or Redo and what queued behind it (`WindowUndoHistory+Failure.swift`).
    @ObservationIgnored var failure = UndoFailureBlock()
    @ObservationIgnored private let changes: any TransactionChangesUseCase
    @ObservationIgnored let loadLedger: any LoadTransactionLedgerUseCase
    @ObservationIgnored private let updates: LedgerUpdates
    /// Runs work after the current Undo or Redo returns, when the `UndoManager` takes steps again.
    @ObservationIgnored let later: (@escaping @MainActor () -> Void) -> Void
    /// Speaks "Undid …" and "Redid …" for VoiceOver (D162.4); the window sets it.
    @ObservationIgnored public var announce: (String) -> Void = { _ in }

    final class Step {
        let id = UUID()
        /// The user's change and where, "Delete 5 Transactions in Household Card"; Undo and Redo keep it.
        let name: String
        /// What reverting this step applies, and what the last change or revert left, for the stale check.
        var change: TransactionChange
        var outcome: ChangeOutcome
        /// Where the change happened, for the name, the toast and the notice (D165.1, D198).
        let impact: ChangeImpact
        /// The account a whole-account step is about.
        let account: Account?
        /// The name the `UndoManager` shows for it now.
        var title = ""

        init(change: TransactionChange, outcome: ChangeOutcome, impact: ChangeImpact) {
            // The account is in the name, kept as it was when the step was recorded (D198).
            self.name = UndoActionTitle.stepName(of: change, impact: impact)
            self.change = change
            self.outcome = outcome
            self.impact = impact
            if case .removedAccount(let removed) = change.core {
                account = removed.account
            } else {
                account = nil
            }
        }

        /// Every account the step needs, so deleting one of them in this window drops it (D187.9).
        var accountIDs: Set<UUID> { impact.accountIDs.union(change.accountIDs) }
    }

    public init(
        changes: any TransactionChangesUseCase,
        loadLedger: any LoadTransactionLedgerUseCase,
        updates: LedgerUpdates,
        later: @escaping (@escaping @MainActor () -> Void) -> Void = { work in Task { @MainActor in work() } },
    ) {
        self.changes = changes
        self.loadLedger = loadLedger
        self.updates = updates
        self.later = later
        updates.add(self)
    }

    // MARK: Window

    /// The window's `UndoManager`. When the window gets a new one, the old one's steps go with it.
    public func attach(_ registrar: (any UndoRegistrar)?) {
        guard registrar !== self.registrar else {
            return
        }
        clear()
        self.registrar = registrar
        observation = registrar?.observeChanges { [weak self] event in self?.managerChanged(event) }
        refreshMenu()
    }

    /// Removes every step of this window from its `UndoManager`, after the ledger was replaced.
    func clear() {
        endFailure()
        for step in undoSteps + redoSteps {
            registrar?.removeSteps(for: step)
        }
        undoSteps.removeAll()
        redoSteps.removeAll()
        closeFeedback()
        refreshMenu()
    }

    /// What the window shows, for the toast and the off-screen notice. Step names don't depend on it: they
    /// always say where the change happened (D198).
    public func setScreen(_ screen: UndoScreen) {
        self.screen = screen
    }

    /// Copies the window's Undo and Redo into the toolbar's state, e.g. after typing in a field (W5). Only a
    /// value that changed is written, so reading the state never makes a view draw again.
    func refreshMenu() {
        let managerCanUndo = registrar?.canUndo ?? false
        let managerCanRedo = registrar?.canRedo ?? false
        // From a failure until its alert is dismissed, Undo and Redo are off; the titles still name the steps
        // (X8b, D193).
        let nextCanUndo = managerCanUndo && !failure.isBlocked
        let nextCanRedo = managerCanRedo && !failure.isBlocked
        let nextUndoTitle = registrar.flatMap {
            managerCanUndo && !$0.undoActionName.isEmpty ? $0.undoActionName : nil
        }
        let nextRedoTitle = registrar.flatMap {
            managerCanRedo && !$0.redoActionName.isEmpty ? $0.redoActionName : nil
        }
        if canUndo != nextCanUndo {
            canUndo = nextCanUndo
        }
        if canRedo != nextCanRedo {
            canRedo = nextCanRedo
        }
        if undoTitle != nextUndoTitle {
            undoTitle = nextUndoTitle
        }
        if redoTitle != nextRedoTitle {
            redoTitle = nextRedoTitle
        }
    }

    // MARK: Recording

    /// Records a change the user just made in this window and returns its step's id. Any toast or notice
    /// closes (D164.2). Deleting an account replaces this window's steps for it with this one (D187.9).
    @discardableResult
    public func record(_ change: TransactionChange) -> UUID {
        var impact = ChangeImpact()
        var newAlert: UndoAlert?
        do {
            impact = try changes.impact(of: change)
        } catch {
            // The step still records; its name just can't say where the change was, so say so.
            newAlert = UndoAlert(title: Self.changeFailedTitle, message: Self.unreadablePlace)
        }
        // Without what the change left, Undo couldn't tell a stale step, so there is no step (D187.5).
        let outcome: ChangeOutcome? = try? changes.outcome(of: change)
        if outcome == nil {
            newAlert = UndoAlert(title: Self.changeFailedTitle, message: Self.unreadableChange)
        }
        let step = Step(change: change, outcome: outcome ?? ChangeOutcome(), impact: impact)
        if let account = step.account {
            for old in (undoSteps + redoSteps) where old.accountIDs.contains(account.id) {
                registrar?.removeSteps(for: old)
            }
            undoSteps.removeAll { $0.accountIDs.contains(account.id) }
        }
        closeFeedback()
        endFailure()
        alert = newAlert
        // A new step clears Redo, as the `UndoManager` does.
        redoSteps.removeAll()
        if registrar != nil, outcome != nil {
            undoSteps.append(step)
            register(step, as: title(of: step))
        }
        updates.changed()
        refreshMenu()
        return step.id
    }

    /// The title of the alerts after a change, never a failed Undo or Redo (D204).
    static var changeFailedTitle: String { UndoText.changeFailedTitle }
    /// Shown when the accounts a change touched couldn't be read.
    static var unreadablePlace: String { UndoText.unreadablePlace }
    /// Shown when the change's records couldn't be read back, so it can't be checked and isn't kept.
    static var unreadableChange: String { UndoText.unreadableChange }

    // MARK: Undo and Redo

    /// The toolbar Undo: the window's own Undo, as Cmd-Z.
    public func undo() {
        guard !failure.isBlocked else {
            return
        }
        registrar?.undo()
        refreshMenu()
    }

    public func redo() {
        guard !failure.isBlocked else {
            return
        }
        registrar?.redo()
        refreshMenu()
    }

    private func title(of step: Step) -> String {
        step.name
    }

    /// Registers the step under `title`: on Undo, or on Redo while it is being undone.
    func register(_ step: Step, as title: String) {
        step.title = title
        registrar?
            .registerStep(step, named: title) { [weak self, weak step] in
                guard let self, let step else {
                    return
                }
                self.run(step)
            }
    }

    /// Undo or Redo of `step`, from the Edit menu, a shortcut, shake, the toolbar or the toast.
    private func run(_ step: Step) {
        failure.handlerRan = true
        let undoing = !(registrar?.isRedoing ?? false)
        let shown = step.title
        undoSteps.removeAll { $0 === step }
        redoSteps.removeAll { $0 === step }
        if failure.isBlocked {
            // A command queued behind a failure, or given before its alert was dismissed: applies nothing (X8b).
            swallow(step, undoing: undoing, title: shown)
            return
        }
        closeFeedback()
        refreshMenu()
        do {
            switch try changes.revert(step.change, expecting: step.outcome) {
            case .reverted(let inverse, let outcome):
                step.change = inverse
                step.outcome = outcome
                alert = nil
                notice = noticeAfterApplying(step)
                if undoing {
                    redoSteps.append(step)
                } else {
                    undoSteps.append(step)
                }
                // Registered while the `UndoManager` undoes, it lands on Redo, and the other way round.
                register(step, as: title(of: step))
                announce(undoing ? UndoText.undid(shown) : UndoText.redid(shown))
                updates.changed()
            case .stale(let reason):
                // Nothing was written, and the step goes (D187.5).
                dropAfterwards(step)
                alert = UndoAlert(
                    title: undoing ? StaleText.cantUndo(shown) : StaleText.cantRedo(shown),
                    message: staleMessage(reason, step),
                )
            }
        } catch {
            fail(step, undoing: undoing, title: shown, error: error)
        }
    }

    /// An `UndoManager` keeps the empty group a Redo leaves when its handler registers nothing, so the menu
    /// would offer an Undo that does nothing. A marker goes in that group instead, and once the Redo (or Undo)
    /// has returned, every action for the step is removed, the marker and its group with it.
    private func dropAfterwards(_ step: Step) {
        registrar?.registerStep(step, named: step.title) {}
        // The step is held until then: the `UndoManager` doesn't keep its targets.
        later { [weak self] in
            self?.registrar?.removeSteps(for: step)
            self?.refreshMenu()
        }
    }

    public func dismissAlert() {
        alert = nil
        if failure.isBlocked {
            // The block ends once the deferred work has put the stand-ins back, never before (X8b).
            failure.isDismissed = true
            endBlockIfFinished()
        }
    }

    // MARK: Toast and notice

    /// Shows the delete toast for a step just recorded (iOS and iPadOS only, D164.1). Like the Undo title, it
    /// says where, "… in Household Card", "… in 2 Accounts" or "… from Household Card to Everyday Savings",
    /// unless the step is on the window's screen (D165.1, D166.5).
    public func showToast(_ message: String, figure: String? = nil, for stepID: UUID) {
        guard let step = undoSteps.last, step.id == stepID else {
            return
        }
        toast = UndoToast(
            stepID: stepID,
            message: UndoActionTitle.name(message, impact: step.impact, on: screen),
            figure: figure,
        )
    }

    /// The toast's Undo: the window's Undo, only while the toast's step is still the newest (D187.7).
    public func undoToast() {
        guard let toast, let step = undoSteps.last, step.id == toast.stepID,
            registrar?.undoActionName == step.title
        else {
            self.toast = nil
            return
        }
        undo()
    }

    /// Closes the toast, after its time or when its list goes away.
    public func dismissToast() {
        toast = nil
    }

    public func dismissNotice() {
        notice = nil
    }

    private func closeFeedback() {
        toast = nil
        notice = nil
    }

    /// "Restored 5 transactions in Household Card" when the step is in an account other than the one on this
    /// window's screen, by the same test as the names; `nil` when it's on screen, even scrolled out of view
    /// (D187.6, N1, N2).
    private func noticeAfterApplying(_ step: Step) -> UndoNotice? {
        if let account = step.account {
            if screen == .account(account.id) {
                return nil
            }
            let restoring = if case .addedAccount = step.change.core { true } else { false }
            return UndoNotice(
                message: restoring ? UndoText.restoredAccount(account.name) : UndoText.deletedAccount(account.name),
                accountID: restoring ? account.id : nil,
            )
        }
        let accounts = step.impact.accounts
        guard !accounts.isEmpty, UndoActionTitle.isOffScreen(step.impact, on: screen) else {
            return nil
        }
        let count = step.change.transactionIDs.count
        // `step.change` is the inverse now: an Undo of a delete leaves `.added`, and so on.
        let effect: UndoText.Effect =
            switch step.change.core {
            case .added: .restored
            case .removed: .deleted
            case .replaced, .removedAccount, .addedAccount, .createdPayees, .removedPayees: .updated
            }
        return UndoNotice(
            message: UndoActionTitle.placed(UndoText.notice(effect, count: count), step.impact),
            accountID: accounts.first?.id,
        )
    }
}

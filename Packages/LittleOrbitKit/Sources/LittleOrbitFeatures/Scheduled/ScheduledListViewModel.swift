import Foundation
import LittleOrbitDomain
import Observation

/// The Scheduled list (#26 design: Overdue, Due today, Upcoming, then Completed). Each missed occurrence has its own
/// row with Pay Now and Skip (S76); Pay Now records today with the occurrence's own key, so paying it twice, or
/// from two windows, records it once. Neither is an Undo step yet, and neither shows a toast (D290). It depends only
/// on use-case protocols.
@MainActor
@Observable
public final class ScheduledListViewModel {
    public private(set) var listing = ScheduledListing(
        board: ScheduledBoard(today: CalendarDay(year: 1970, month: 1, day: 1))
    ) {
        didSet { rebuildTable() }
    }
    public var alert: CategoryAlert?
    public var confirmation: ScheduledConfirmation?
    public var form: ScheduledFormViewModel?
    /// Records a form save in this window's undo history, with its name, "New Scheduled Item Rent" or "Edit Rent",
    /// and the item's name for a stale alert (D351.1). The window sets it; without it, nothing is recorded.
    @ObservationIgnored public var recordStep: ScheduledStepRecorder = { _, _, _ in }

    /// The Scheduled screens on screen, in the order they appeared: the last one presents (see `presenter`).
    public private(set) var visibleScreens: [ScheduledScreen] = []
    /// Whether a load has read the listing, so a hint is never judged against the placeholder board, and an item
    /// that isn't read yet never counts as deleted. Observed, so a screen waiting for the first load redraws.
    private var loaded = false
    /// What catch-up recorded that the catch-up hint hasn't reported yet, read at each load (D338.6).
    public private(set) var pendingCatchUp: [ScheduledCatchUpGroup] = []
    /// Whether this list's hint row has actually appeared on screen. Only that marks the hint shown, never a load.
    @ObservationIgnored private var catchUpHintAppearedHere = false
    /// This list left the Scheduled screens after its hint appeared: the notice is gone from app settings, but this
    /// list keeps showing it if it comes back. The Mac's detail column may report the list disappearing and
    /// appearing again while it stays on screen, and that mustn't take away a hint that's still in view.
    @ObservationIgnored private var keepsHintAfterLeaving = false
    /// The deferred "left the Scheduled screens" check from the last `screenDisappeared(.list)`, kept so tests can
    /// await it instead of guessing how many yields it needs.
    @ObservationIgnored private(set) var leavingCheck: Task<Void, Never>?
    public let platform: ScheduledPlatform

    @ObservationIgnored private let useCases: ScheduledScreenUseCases
    @ObservationIgnored let locale: Locale
    /// The Mac Table's sections, built once per listing (Tech Architect NB 1), and its rows by ID.
    public internal(set) var tableSections: [ScheduledTableSection] = []
    @ObservationIgnored var tableRowsByID: [String: ScheduledTableRow] = [:]
    /// The time a notified item's Status names (D355.2): Settings › Reminder Time, 09:00 until that's built (#204).
    @ObservationIgnored public var reminderTime = DateComponents(hour: 9, minute: 0) {
        didSet { rebuildTable() }
    }
    @ObservationIgnored private let changed: () -> Void

    public init(
        useCases: ScheduledScreenUseCases,
        locale: Locale = .current,
        platform: ScheduledPlatform = .current,
        changed: @escaping () -> Void = {},
    ) {
        self.useCases = useCases
        self.locale = locale
        self.platform = platform
        self.changed = changed
    }

    var rows: ScheduledPresenter {
        ScheduledPresenter(listing: listing, locale: locale)
    }

    // MARK: Reading

    public func load() {
        do {
            listing = try useCases.load.listing()
            loaded = true
        } catch {
            alert = ScheduledText.loadFailed
        }
        let stored = useCases.notices.pending()
        if !stored.isEmpty || !keepsHintAfterLeaving {
            pendingCatchUp = stored
            keepsHintAfterLeaving = false
        }
        forgetCatchUpHintWithNothingToName()
    }

    /// Reads the listing unless a load has: a history row's item sheet opens on a new model (Tester's #203 FAIL).
    public func loadIfNeeded() {
        if !loaded {
            load()
        }
    }

    /// Deleted here or in another window. Before the first load nothing is gone, as the listing is a placeholder.
    public func isGone(_ itemID: UUID) -> Bool {
        loaded && listing.item(itemID) == nil
    }

    /// While the list is on screen, a pending catch-up hint with nothing left to name (its items were deleted) is
    /// forgotten (D338.6).
    private func forgetCatchUpHintWithNothingToName() {
        guard loaded, visibleScreens.contains(.list), !pendingCatchUp.isEmpty, catchUpHint == nil else {
            return
        }
        useCases.notices.clear()
        pendingCatchUp = []
    }

    /// The hint row appeared on screen: only now does the hint count as shown (D338.6).
    public func catchUpHintAppeared() {
        guard loaded, catchUpHint != nil else {
            return
        }
        catchUpHintAppearedHere = true
        useCases.notices.markShown()
    }

    // MARK: Presenting

    /// The screen on top, which attaches the sheet, the confirmations and the alert. Only that one presents, so a
    /// pushed item or Completed screen shows them, and the list under it never presents them twice.
    public var presenter: ScheduledScreen {
        visibleScreens.last ?? .list
    }

    public func screenAppeared(_ screen: ScheduledScreen) {
        visibleScreens.removeAll { $0 == screen }
        visibleScreens.append(screen)
        if screen == .list {
            forgetCatchUpHintWithNothingToName()
        }
    }

    public func screenDisappeared(_ screen: ScheduledScreen) {
        visibleScreens.removeAll { $0 == screen }
        // Leaving the Scheduled screens, not pushing onto the list, ends a shown catch-up hint (D338.6). A push may
        // report the list's disappearance before the pushed screen's appearance, so this looks after both.
        guard screen == .list, visibleScreens.isEmpty else {
            return
        }
        leavingCheck = Task { @MainActor [weak self] in
            await Task.yield()
            if let self, self.visibleScreens.isEmpty {
                self.leftScheduled()
            }
        }
    }

    /// The list left the Scheduled screens: a shown hint goes from app settings, so the next visit doesn't show it,
    /// but one that appeared in this list stays in this list in case it was only re-shown in place (D338.6).
    private func leftScheduled() {
        useCases.notices.dismissIfShown()
        if catchUpHintAppearedHere && !pendingCatchUp.isEmpty {
            keepsHintAfterLeaving = true
        } else {
            pendingCatchUp = useCases.notices.pending()
        }
    }

    /// The Scheduled screens were left: a catch-up hint they showed goes; one they haven't shown yet stays (D338.6).
    public func dismissCatchUpHint() {
        useCases.notices.dismissIfShown()
        pendingCatchUp = useCases.notices.pending()
        catchUpHintAppearedHere = false
        keepsHintAfterLeaving = false
    }

    /// The one way this model's extensions write (Pay Now, Skip and Delete): `change` gets the manage use cases,
    /// a failure shows the save-failed alert, and the list reloads and reports the change. Views never call it:
    /// they use the actions, which ask first and record what they must (Tech Architect 5661097037 NB1).
    func run(_ change: (any ManageScheduledUseCase) throws -> Void) {
        perform { try change(useCases.manage) }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            alert = ScheduledText.saveFailed
        }
        load()
        changed()
    }

    // MARK: Form

    /// "New Scheduled Item Rent" or "Edit Rent", named as the list names the item (D351.1). Delete is never an
    /// Undo step (D334.9).
    func recordSave(_ change: ScheduledItemSaveChange) {
        let name = rows.shortName(of: change.after)
        recordStep(.savedScheduledItem(change), ScheduledText.saveStepName(change, name: name), name)
    }

    public func openNew() {
        form = makeForm(nil)
    }

    public func openEditor(_ itemID: UUID) {
        guard let item = listing.item(itemID) else {
            return
        }
        form = makeForm(item)
    }

    private func makeForm(_ item: ScheduledItem?) -> ScheduledFormViewModel {
        ScheduledFormViewModel(
            useCases: useCases,
            listing: listing,
            editing: item,
            locale: locale,
            platform: platform,
        ) { [weak self] in
            let change = $0
            self?.load()
            self?.recordSave(change)
            self?.changed()
        }
    }
}

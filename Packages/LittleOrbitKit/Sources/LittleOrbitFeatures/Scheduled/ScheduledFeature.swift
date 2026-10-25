import Foundation
import LittleOrbitDomain

/// The use cases the Scheduled screens need, from the composition root.
@MainActor
public struct ScheduledScreenUseCases {
    public var load: any LoadScheduledUseCase
    public var manage: any ManageScheduledUseCase
    public var catchUp: any CatchUpScheduledUseCase
    /// What catch-up recorded while the app was closed, for the list's hint. One per launch, shared by windows.
    public var notices: any ScheduledCatchUpNoticeUseCase

    public init(
        load: any LoadScheduledUseCase,
        manage: any ManageScheduledUseCase,
        catchUp: any CatchUpScheduledUseCase,
        notices: any ScheduledCatchUpNoticeUseCase = ScheduledCatchUpNotices(),
    ) {
        self.load = load
        self.manage = manage
        self.catchUp = catchUp
        self.notices = notices
    }
}

/// Everything the Scheduled screens need (#26), built once by the composition root. It records due automatic
/// occurrences, each once, and counts the home row and badge (D106). Each window makes its own list model.
@MainActor
public final class ScheduledFeature: PlannedItemsSource {
    public let useCases: ScheduledScreenUseCases
    private let updates: LedgerUpdates?
    private let locale: Locale
    /// Called when a catch-up couldn't run or left some items unrecorded; the App logs it with no user data.
    private let onCatchUpProblem: (ScheduledCatchUpProblem) -> Void
    /// The clock-ahead line is logged once per launch, not on every activation (Tech Architect NB 1). The feature
    /// is built once per launch.
    private var reportedCreatedAfterToday = false
    /// Removes the restore handler if this feature is ever replaced while `updates` lives on.
    private var ledgerReplacedHandler: LedgerUpdates.ReplacedHandler?

    /// `updates` tells every window to reload after a scheduled change, as a transaction change does.
    public init(
        useCases: ScheduledScreenUseCases,
        updates: LedgerUpdates? = nil,
        locale: Locale = .current,
        onCatchUpProblem: @escaping (ScheduledCatchUpProblem) -> Void = { _ in },
    ) {
        self.useCases = useCases
        self.updates = updates
        self.locale = locale
        self.onCatchUpProblem = onCatchUpProblem
        // A restore replaces the ledger, so a pending catch-up hint could name days it no longer has (Tech
        // Architect NB 1).
        ledgerReplacedHandler = updates?.onLedgerReplaced { [notices = useCases.notices] in notices.clear() }
    }

    /// Records every due occurrence of the automatic items, each once, dated on its own due day. The App calls it
    /// at launch before the accounts and badge load (`atLaunch`), and whenever the app becomes active. It's outside
    /// undo history (D187.2). Running it twice, from two windows or after a clock change records nothing more.
    @discardableResult
    public func catchUp(atLaunch: Bool) -> ScheduledCatchUp? {
        let result: ScheduledCatchUp
        do {
            result = try useCases.catchUp.catchUp(atLaunch: atLaunch)
        } catch {
            onCatchUpProblem(.failed(error))
            return nil
        }
        if !result.failedItemIDs.isEmpty {
            onCatchUpProblem(.someNotRecorded)
        }
        if !result.createdAfterTodayItemIDs.isEmpty && !reportedCreatedAfterToday {
            reportedCreatedAfterToday = true
            onCatchUpProblem(.createdAfterToday)
        }
        // The list's info hint says what was recorded while the app was closed, until the list has shown it.
        useCases.notices.add(result)
        if result.changedLedger {
            updates?.changed()
        }
        return result
    }

    public func plannedItemCounts() -> PlannedItemCounts {
        guard let board = try? useCases.load.listing().board else {
            return PlannedItemCounts()
        }
        return PlannedItemCounts(scheduledItemCount: board.itemCount, overdueOccurrenceCount: board.overdueCount)
    }

    public func makeList() -> ScheduledListViewModel {
        ScheduledListViewModel(useCases: useCases, locale: locale) { [weak updates] in updates?.changed() }
    }

    /// The ledger revision every window follows, so a screen reloads after a change made elsewhere.
    public var revision: Int {
        updates?.revision ?? 0
    }

    /// Stops clearing the catch-up hint on restore, for a feature that's replaced while `updates` lives on.
    public func stopFollowingRestores() {
        guard let ledgerReplacedHandler else {
            return
        }
        updates?.removeLedgerReplacedHandler(ledgerReplacedHandler)
        self.ledgerReplacedHandler = nil
    }
}

/// Why a catch-up needs a log line. Never carries names, amounts or paths.
public enum ScheduledCatchUpProblem {
    case failed(any Error)
    case someNotRecorded
    /// Some items' creation day is after today: the device clock was ahead when they were made.
    case createdAfterToday
}

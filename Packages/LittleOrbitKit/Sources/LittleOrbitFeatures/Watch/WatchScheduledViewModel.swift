import Foundation
import LittleOrbitDomain
import Observation

/// The watch's Scheduled screens (#32, #197 item 10): the list from the iPhone's snapshot, the Pay and Skip screen
/// of one occurrence, the syncing marks, and the message when the iPhone turns a request down. It reads and acts
/// only through `WatchScheduledUseCase`; it never sees WatchConnectivity or a store.
@MainActor
@Observable
public final class WatchScheduledViewModel {
    public private(set) var rows: [WatchScheduledRow] = []
    /// No snapshot has arrived from the iPhone yet.
    public private(set) var isWaitingForIPhone = true
    /// The message for a Pay or Skip the iPhone turned down, until OK closes it.
    public private(set) var conflict: WatchConflict?

    @ObservationIgnored private let useCases: any WatchScheduledUseCase
    @ObservationIgnored private let presenter: WatchScheduledPresenter

    public init(useCases: any WatchScheduledUseCase, locale: Locale = .current) {
        self.useCases = useCases
        presenter = WatchScheduledPresenter(locale: locale)
        useCases.onChange { [weak self] in self?.reload() }
        reload()
    }

    public var title: String { ScheduledText.title }
    public var emptyTitle: String { ScheduledText.emptyTitle }
    /// Before the first snapshot (UI Designer 6406964245); after it, an empty list shows `emptyTitle`.
    public var notSyncedTitle: String { WatchText.notSyncedTitle }
    public var notSyncedMessage: String { WatchText.notSyncedMessage }
    public var payTitle: String { WatchText.pay }
    public var skipTitle: String { ScheduledText.skip }
    public var isEmpty: Bool { rows.isEmpty }

    public func row(_ id: UUID) -> WatchScheduledRow? {
        rows.first { $0.id == id }
    }

    public func reload() {
        let state = useCases.state()
        rows = presenter.rows(state)
        isWaitingForIPhone = state.snapshot == nil
        conflict = presenter.conflict(state)
    }

    /// Pay: sent to the iPhone, which records it once, dated today on the watch. The row shows "Paid · syncing"
    /// until the iPhone answers.
    public func pay(_ id: UUID) {
        guard let row = row(id), !row.isPending else {
            return
        }
        useCases.pay(row.occurrence)
    }

    public func skip(_ id: UUID) {
        guard let row = row(id), !row.isPending else {
            return
        }
        useCases.skip(row.occurrence)
    }

    /// The watch app opened or became active: a Pay or Skip not delivered yet goes out again once its wait is
    /// over. Its row stays syncing meanwhile (D377).
    public func appBecameActive() {
        useCases.retryPending()
    }

    /// OK on the message.
    public func closeConflict() {
        guard let conflict else {
            return
        }
        useCases.acknowledge(requestID: conflict.id)
    }
}

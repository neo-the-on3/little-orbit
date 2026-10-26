import Foundation
import LittleOrbitDomain
import Observation

/// The card at the top of the iPhone's Scheduled list for watch Pay and Skip requests it didn't apply (D374, D375,
/// D376; UI Designer 6406964245).
public struct WatchRequestNoticeCard: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let message: String
    /// The item View Item opens; `nil` for a grouped card or a newer-watch one, which have only OK.
    public let itemID: UUID?
    /// The requests OK dismisses.
    let noticeIDs: Set<UUID>
}

/// One card at a time, oldest first: one request's notice names its item, and several with the same reason share
/// one card with their count. OK dismisses it for good, then the next one shows. It reads and dismisses only through
/// `WatchRequestNoticesUseCase`. One instance is shared by every window's Scheduled list.
@MainActor
@Observable
public final class WatchRequestNoticeViewModel {
    public private(set) var card: WatchRequestNoticeCard?

    @ObservationIgnored private let useCases: any WatchRequestNoticesUseCase

    public init(useCases: any WatchRequestNoticesUseCase) {
        self.useCases = useCases
        reload()
    }

    public var okTitle: String { WatchRequestNoticeText.okay }
    public var viewItemTitle: String { WatchRequestNoticeText.viewItem }

    /// Reads what's pending: at launch, when the Scheduled list appears and when the iPhone queues a notice.
    public func reload() {
        let entries = useCases.pendingNotices()
        guard let first = entries.first else {
            card = nil
            return
        }
        let group = entries.filter { $0.notice.reason == first.notice.reason }
        card = group.count == 1 ? Self.single(first) : Self.grouped(group)
    }

    /// Where View Item goes: the item's own screen, mapped by the list to its stack's route (`AccountsRoute` on
    /// iPhone and iPad, #198). `nil` when the card has no View Item.
    public var viewItemRoute: ScheduledRoute? {
        card?.itemID.map(ScheduledRoute.item)
    }

    /// OK: the card never shows again.
    public func dismiss() {
        guard let card else {
            return
        }
        useCases.dismissNotices(card.noticeIDs)
        reload()
    }

    static func single(_ entry: WatchRequestNoticeEntry) -> WatchRequestNoticeCard {
        let notice = entry.notice
        switch (notice.reason, notice.action, entry.item) {
        case (.itemChanged, let action?, let item?):
            let name = ScheduledPresenter.name(
                details: item.details,
                payee: item.payeeName,
                type: item.type,
                transferTarget: item.transferAccountName,
                category: item.categoryName,
            )
            let isPay = action == .pay
            return WatchRequestNoticeCard(
                id: notice.id,
                title: isPay ? WatchRequestNoticeText.payTitle : WatchRequestNoticeText.skipTitle,
                message: WatchText.sentences(
                    isPay ? WatchRequestNoticeText.payChanged(name) : WatchRequestNoticeText.skipChanged(name),
                    isPay ? WatchRequestNoticeText.payAgain : WatchRequestNoticeText.skipAgain,
                ),
                itemID: notice.itemID,
                noticeIDs: [notice.id],
            )
        case (.newerWatchApp, let action?, _):
            let isPay = action == .pay
            return WatchRequestNoticeCard(
                id: notice.id,
                title: WatchRequestNoticeText.updateTitle,
                message: WatchText.sentences(
                    isPay ? WatchRequestNoticeText.payNewer : WatchRequestNoticeText.skipNewer,
                    isPay ? WatchRequestNoticeText.payNewerAgain : WatchRequestNoticeText.skipNewerAgain,
                ),
                itemID: nil,
                noticeIDs: [notice.id],
            )
        default:
            // A newer request whose action didn't read: the grouped wording, with its count of one.
            return grouped([entry])
        }
    }

    static func grouped(_ entries: [WatchRequestNoticeEntry]) -> WatchRequestNoticeCard {
        let count = entries.count
        let isNewer = entries.first?.notice.reason == .newerWatchApp
        return WatchRequestNoticeCard(
            id: entries.first?.id ?? UUID(),
            title: isNewer ? WatchRequestNoticeText.updateTitle : WatchRequestNoticeText.severalChangedTitle,
            message: WatchText.sentences(
                isNewer ? WatchRequestNoticeText.severalNewer(count) : WatchRequestNoticeText.severalChanged(count),
                isNewer ? WatchRequestNoticeText.severalNewerAgain : WatchRequestNoticeText.severalChangedAgain(count),
            ),
            itemID: nil,
            noticeIDs: Set(entries.map(\.id)),
        )
    }
}

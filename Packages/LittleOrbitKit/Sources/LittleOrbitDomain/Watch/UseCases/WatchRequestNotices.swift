import Foundation

/// A watch request from a newer watch build, as far as this iPhone build can read it (D376).
public struct WatchNewerRequest: Hashable, Sendable {
    public var id: UUID
    /// `nil` when even that no longer reads.
    public var action: WatchScheduledRequest.Action?

    public init(id: UUID, action: WatchScheduledRequest.Action?) {
        self.id = id
        self.action = action
    }
}

/// A watch Pay or Skip the iPhone didn't apply, which it tells the user about once on the Scheduled list (D374,
/// D376). It waits in the inbox until OK dismisses it. IDs only: the item's name is read when it's shown. The
/// request itself isn't kept, so nothing replays it later.
public struct WatchRequestNotice: Codable, Hashable, Sendable, Identifiable {
    public enum Reason: String, Codable, Sendable {
        /// The item changed on the iPhone before the request arrived (D374).
        case itemChanged
        /// The request came from a newer watch build than this iPhone build reads (D376).
        case newerWatchApp
    }

    /// The request's ID.
    public var id: UUID
    public var reason: Reason
    public var action: WatchScheduledRequest.Action?
    public var itemID: UUID?

    public init(id: UUID, reason: Reason, action: WatchScheduledRequest.Action?, itemID: UUID?) {
        self.id = id
        self.reason = reason
        self.action = action
        self.itemID = itemID
    }

    private enum CodingKeys: String, CodingKey {
        case id = "q"
        case reason = "r"
        case action = "a"
        case itemID = "i"
    }
}

/// A notice to show, with what its item is called on the iPhone now (an item-changed notice only). Features words
/// it.
public struct WatchRequestNoticeEntry: Equatable, Sendable, Identifiable {
    public struct ItemNames: Equatable, Sendable {
        public var type: TransactionType
        public var details: String?
        public var payeeName: String?
        public var categoryName: String?
        public var transferAccountName: String?

        public init(
            type: TransactionType,
            details: String? = nil,
            payeeName: String? = nil,
            categoryName: String? = nil,
            transferAccountName: String? = nil,
        ) {
            self.type = type
            self.details = details
            self.payeeName = payeeName
            self.categoryName = categoryName
            self.transferAccountName = transferAccountName
        }
    }

    public var notice: WatchRequestNotice
    public var item: ItemNames?

    public init(notice: WatchRequestNotice, item: ItemNames? = nil) {
        self.notice = notice
        self.item = item
    }

    public var id: UUID { notice.id }
}

/// The iPhone's notices for watch requests it didn't apply (D374, D376): each waits, across relaunches, until the
/// user dismisses it on the Scheduled list.
@MainActor
public protocol WatchRequestNoticesUseCase {
    /// The notices not dismissed yet, oldest first. An item-changed one whose item has since been deleted is
    /// dropped: there's nothing left to check.
    func pendingNotices() -> [WatchRequestNoticeEntry]
    /// OK: they never show again.
    func dismissNotices(_ ids: Set<UUID>)
}

extension DefaultWatchPhoneUseCases: WatchRequestNoticesUseCase {
    public func pendingNotices() -> [WatchRequestNoticeEntry] {
        let notices = inbox.notices()
        guard !notices.isEmpty, let ledger = try? repository.scheduleLedger() else {
            return []
        }
        let items = LedgerBook.activeScheduledItems(in: ledger)
        let entries = notices.compactMap { notice -> WatchRequestNoticeEntry? in
            guard notice.reason == .itemChanged else {
                return WatchRequestNoticeEntry(notice: notice)
            }
            guard let item = items.first(where: { $0.id == notice.itemID }) else {
                return nil
            }
            let details = item.details?.trimmingCharacters(in: .whitespacesAndNewlines)
            let names = WatchRequestNoticeEntry.ItemNames(
                type: item.type,
                details: details?.isEmpty == false ? details : nil,
                payeeName: ledger.payees.first { $0.id == item.payeeID }?.name,
                categoryName: ledger.categories.first { $0.id == item.categoryID }?.name,
                transferAccountName: ledger.accounts.first { $0.id == item.transferAccountID }?.name,
            )
            return WatchRequestNoticeEntry(notice: notice, item: names)
        }
        if entries.count != notices.count {
            inbox.setNotices(entries.map(\.notice))
        }
        return entries
    }

    public func dismissNotices(_ ids: Set<UUID>) {
        let notices = inbox.notices()
        let remaining = notices.filter { !ids.contains($0.id) }
        if remaining.count != notices.count {
            inbox.setNotices(remaining)
        }
    }

    /// A request from a newer watch build (D376): nothing is applied or kept to replay. The iPhone answers it
    /// `unsupported`, so the watch clears its syncing mark, and queues its notice once.
    @discardableResult
    public func receiveNewer(_ request: WatchNewerRequest) -> WatchApplyRun {
        var answered = inbox.outcomes()
        if let earlier = answered.first(where: { $0.requestID == request.id }) {
            return WatchApplyRun(outcomes: [earlier])
        }
        let outcome = WatchRequestOutcome(requestID: request.id, result: .unsupported)
        answered.append(outcome)
        inbox.setOutcomes(Array(answered.suffix(Self.rememberedOutcomes)))
        queue(WatchRequestNotice(id: request.id, reason: .newerWatchApp, action: request.action, itemID: nil))
        return WatchApplyRun(outcomes: [outcome], queuedNotices: 1)
    }

    func queue(_ notice: WatchRequestNotice) {
        var notices = inbox.notices()
        notices.append(notice)
        inbox.setNotices(Array(notices.suffix(Self.rememberedOutcomes)))
    }
}

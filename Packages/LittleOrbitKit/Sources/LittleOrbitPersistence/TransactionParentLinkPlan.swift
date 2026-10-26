import Foundation
import LittleOrbitDomain

/// #265: what a large write changes in the to-many links of its transactions' accounts, payees, categories and
/// tags, so SwiftData can be given one assignment per parent instead of a to-one change per transaction, each of
/// which makes it update a link that can hold thousands (Tester2's 40–80 s writes on main, 67–84 s Undo Import).
/// New transactions are only added; an edited one leaves the parents it no longer has and joins the new ones;
/// one whose parents stay the same changes nothing, so the transactions a write doesn't change are never touched.
/// Plain values, so it runs and is tested on every platform.
struct TransactionParentLinkPlan: Equatable {
    /// The parent's to-many link that holds a transaction.
    enum Link: CaseIterable, Hashable {
        case account
        case transferAccount
        case category
        case payee
        case tag
    }

    /// What one parent's link loses and gains: transaction ids, the gained ones in the order written.
    struct Change: Equatable {
        var removed: Set<UUID> = []
        var added: [UUID] = []
    }

    /// For each link, each parent whose link changes.
    private(set) var changes: [Link: [UUID: Change]] = [:]

    /// `upserted` as the write leaves them; `stored` the ones already in the store, by id, as stored.
    init(writing upserted: [Transaction], over stored: [UUID: Transaction]) {
        for transaction in upserted {
            let before = stored[transaction.id]
            for link in Link.allCases {
                let old = before.map { Self.parents(of: $0, in: link) } ?? []
                let new = Self.parents(of: transaction, in: link)
                for parent in old.subtracting(new) {
                    changes[link, default: [:]][parent, default: Change()].removed.insert(transaction.id)
                }
                for parent in Self.ordered(new.subtracting(old)) {
                    changes[link, default: [:]][parent, default: Change()].added.append(transaction.id)
                }
            }
        }
    }

    /// The parents whose `link` changes, in a fixed order, with their change.
    func changes(in link: Link) -> [(parent: UUID, change: Change)] {
        Self.ordered(Set((changes[link] ?? [:]).keys))
            .compactMap { parent in
                changes[link]?[parent].map { (parent, $0) }
            }
    }

    static func parents(of transaction: Transaction, in link: Link) -> Set<UUID> {
        switch link {
        case .account: Set([transaction.accountID].compactMap(\.self))
        case .transferAccount: Set([transaction.transferAccountID].compactMap(\.self))
        case .category: Set([transaction.categoryID].compactMap(\.self))
        case .payee: Set([transaction.payeeID].compactMap(\.self))
        case .tag: Set(transaction.tagIDs)
        }
    }

    private static func ordered(_ ids: Set<UUID>) -> [UUID] {
        ids.sorted { $0.uuidString < $1.uuidString }
    }
}

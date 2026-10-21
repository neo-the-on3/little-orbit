import Foundation

/// Moves accounts within one section with fractional `sortOrder` values (#11).
///
/// Only the moved account changes, taking the midpoint of its new neighbours. When the neighbours leave no room
/// (equal or too close), the whole section is renumbered 1, 2, 3, … so the new order still sticks.
///
/// The list on screen can leave hidden accounts out. Pass the whole section as `within` so the move is worked out
/// against every account in it: hidden accounts count as neighbours and are renumbered with the rest, so they keep
/// their place when "Show hidden accounts" is turned on (D109).
public struct ReorderAccounts: Sendable {
    public init() {}

    /// - Parameters:
    ///   - shown: the section as the list shows it, in display order.
    ///   - fromOffsets, toOffset: the same values SwiftUI's `onMove` passes, as offsets into `shown`.
    ///   - section: the whole section in display order, hidden accounts included. Defaults to `shown`.
    /// - Returns: the accounts whose `sortOrder` changed.
    public func callAsFunction(
        _ shown: [Account],
        fromOffsets: IndexSet,
        toOffset: Int,
        within section: [Account]? = nil,
    ) -> [Account] {
        let section = section ?? shown
        let movingIDs = Set(fromOffsets.map { shown[$0].id })
        let moving = fromOffsets.map { shown[$0] }
        // The first account at or after the drop point that stays put. The moved accounts go just before it.
        let anchorID = shown[min(toOffset, shown.count)...].first { !movingIDs.contains($0.id) }?.id
        var reordered = section.filter { !movingIDs.contains($0.id) }
        let insertion: Int
        if let anchorID, let index = reordered.firstIndex(where: { $0.id == anchorID }) {
            insertion = index
        } else if let lastStaying = shown.last(where: { !movingIDs.contains($0.id) }),
            let index = reordered.firstIndex(where: { $0.id == lastStaying.id })
        {
            insertion = index + 1
        } else {
            return []
        }
        reordered.insert(contentsOf: moving, at: insertion)
        if reordered.map(\.id) == section.map(\.id) {
            return []
        }
        if moving.count == 1, let placed = midpoint(for: insertion, in: reordered) {
            var account = reordered[insertion]
            account.sortOrder = placed
            return [account]
        }
        return renumbered(reordered, comparedTo: section)
    }

    /// The `sortOrder` for a new account: after every existing one.
    public static func nextSortOrder(after accounts: [Account]) -> Double {
        (accounts.map(\.sortOrder).max() ?? 0) + 1
    }

    private func midpoint(for index: Int, in accounts: [Account]) -> Double? {
        let previous = index > 0 ? accounts[index - 1].sortOrder : nil
        let next = index + 1 < accounts.count ? accounts[index + 1].sortOrder : nil
        let value: Double
        switch (previous, next) {
        case (let low?, let high?):
            value = (low + high) / 2
            guard low < value, value < high else {
                return nil
            }
        case (let low?, nil):
            value = low + 1
        case (nil, let high?):
            value = high - 1
        case (nil, nil):
            return nil
        }
        return value
    }

    private func renumbered(_ reordered: [Account], comparedTo original: [Account]) -> [Account] {
        let before = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0.sortOrder) })
        return reordered.enumerated()
            .compactMap { offset, account in
                var account = account
                account.sortOrder = Double(offset + 1)
                return before[account.id] == account.sortOrder ? nil : account
            }
    }
}

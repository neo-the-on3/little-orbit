import Foundation

extension AccountHistoryViewModel {
    /// The transactions `ids` stand for: a split line shown under its row in the macOS table stands for its
    /// split, so selecting the line selects the split (S45).
    public func owningIDs(_ ids: Set<UUID>) -> Set<UUID> {
        let owners = Dictionary(
            allRows.flatMap { row in row.splitLines.map { ($0.id, row.id) } },
            uniquingKeysWith: { first, _ in first },
        )
        return Set(ids.map { owners[$0] ?? $0 })
    }
}

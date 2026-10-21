import Foundation
import LittleOrbitDomain
import Testing

/// Accounts reorder within their section, using fractional sortOrder (#11).
@Suite("Reorder accounts")
struct ReorderAccountsTests {
    private let reorder = ReorderAccounts()

    private func accounts(_ names: String...) -> [Account] {
        names.enumerated()
            .map { index, name in
                Account(name: name, sortOrder: Double(index + 1))
            }
    }

    private func apply(_ changes: [Account], to accounts: [Account]) -> [String] {
        merged(changes, into: accounts).map(\.name)
    }

    private func merged(_ changes: [Account], into accounts: [Account]) -> [Account] {
        var merged = accounts
        for change in changes {
            if let index = merged.firstIndex(where: { $0.id == change.id }) {
                merged[index] = change
            }
        }
        return merged.sorted { $0.sortOrder < $1.sortOrder }
    }

    @Test("Moving C to the top gives C, A, B and changes only C")
    func moveToTop() {
        let list = accounts("A", "B", "C")
        let changes = reorder(list, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(changes.map(\.name) == ["C"])
        #expect(apply(changes, to: list) == ["C", "A", "B"])
    }

    @Test("Moving A to the end gives B, C, A")
    func moveToEnd() {
        let list = accounts("A", "B", "C")
        let changes = reorder(list, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(apply(changes, to: list) == ["B", "C", "A"])
    }

    @Test("Moving into the middle uses the midpoint")
    func moveToMiddle() throws {
        let list = accounts("A", "B", "C")
        let changes = reorder(list, fromOffsets: IndexSet(integer: 0), toOffset: 2)
        let moved = try #require(changes.first)
        #expect(moved.sortOrder == 2.5)
        #expect(apply(changes, to: list) == ["B", "A", "C"])
    }

    @Test("A move onto itself changes nothing")
    func noOp() {
        let list = accounts("A", "B", "C")
        #expect(reorder(list, fromOffsets: IndexSet(integer: 1), toOffset: 1).isEmpty)
        #expect(reorder(list, fromOffsets: IndexSet(integer: 1), toOffset: 2).isEmpty)
    }

    @Test("Equal sort orders are renumbered so the move still sticks")
    func renumbersTies() {
        let list = ["A", "B", "C"].map { Account(name: $0, sortOrder: 0) }
        let changes = reorder(list, fromOffsets: IndexSet(integer: 2), toOffset: 1)
        #expect(apply(changes, to: list) == ["A", "C", "B"])
    }

    @Test("Renumbering includes hidden accounts in the section, which keep their place (D109)")
    func renumberKeepsHiddenInPlace() {
        var section = ["A", "Hidden", "B", "C"].map { Account(name: $0, sortOrder: 0) }
        section[1].isHidden = true
        let shown = section.filter { !$0.isHidden }
        let changes = reorder(shown, fromOffsets: IndexSet(integer: 2), toOffset: 1, within: section)
        #expect(apply(changes, to: section) == ["A", "Hidden", "C", "B"])
        #expect(Set(merged(changes, into: section).map(\.sortOrder)).count == 4, "No two accounts share a sortOrder")
    }

    @Test("A midpoint move counts hidden neighbours, so it never collides with a hidden account (D109)")
    func midpointRespectsHidden() throws {
        var section = accounts("A", "Hidden", "B", "C")
        section[1].isHidden = true
        let shown = section.filter { !$0.isHidden }
        let changes = reorder(shown, fromOffsets: IndexSet(integer: 2), toOffset: 1, within: section)
        let moved = try #require(changes.first)
        #expect(changes.map(\.name) == ["C"])
        #expect(moved.sortOrder == 2.5)
        #expect(apply(changes, to: section) == ["A", "Hidden", "C", "B"])
    }

    @Test("Moving to the top keeps a hidden first account first")
    func moveToTopWithHidden() {
        var section = accounts("Hidden", "A", "B")
        section[0].isHidden = true
        let shown = Array(section.dropFirst())
        let changes = reorder(shown, fromOffsets: IndexSet(integer: 1), toOffset: 0, within: section)
        #expect(apply(changes, to: section) == ["Hidden", "B", "A"])
    }

    @Test("New accounts go after every existing account")
    func nextSortOrder() {
        #expect(ReorderAccounts.nextSortOrder(after: []) == 1)
        #expect(ReorderAccounts.nextSortOrder(after: accounts("A", "B")) == 3)
    }
}

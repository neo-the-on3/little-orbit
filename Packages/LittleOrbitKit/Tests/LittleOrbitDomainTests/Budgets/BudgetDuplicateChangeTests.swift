import Foundation
import LittleOrbitDomain
import Testing

/// Duplicating a budget on the Mac as a revertible change (D307.6, D307.8 Duplicate Budget): the copy gets the next
/// free name, every setting and the whole limit history, so its periods match the original's.
@MainActor
@Suite("Budget duplicate for Undo (#25)")
struct BudgetDuplicateChangeTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFixture  // swiftlint:disable:this type_name

    /// The Finder's names, as the Mac's wording gives them: “‹Name› copy”, then “‹Name› copy 2” and so on.
    private static func copyName(_ name: String, _ number: Int) -> String {
        number == 1 ? "\(name) copy" : "\(name) copy \(number)"
    }

    private func setup(_ budgets: [Budget]) throws -> (FakeBudgetRepository, DefaultBudgetUseCases) {
        let repository = FakeBudgetRepository(try B.saving([], budgets: budgets))
        return (repository, DefaultBudgetUseCases(repository: repository, now: { F.date(2026, 11, 5) }))
    }

    @Test("D307.6: the copy is “‹Name› copy” with every setting and the whole limit history, under a new ID")
    func copiesEverything() throws {
        let original = B.budget(
            categories: [B.restaurantsID, B.groceriesID],
            from: F.day(2026, 9, 1),
            recurrence: .custom(every: 3, unit: .week),
            unspent: true,
            overspending: true,
        )
        let (repository, useCases) = try setup([original])
        try useCases.changeLimit(of: original.id, to: 9_000, today: F.day(2026, 11, 20))
        let stored = try #require(try repository.budgets().first)

        let change = try useCases.duplicatedChange(of: original.id, naming: Self.copyName)
        guard case .added(let copyID) = change else {
            Issue.record("Not an added budget: \(change)")
            return
        }
        let copy = try #require(try repository.budgets().first { $0.id == copyID })
        #expect(copy.id != original.id)
        #expect(copy.name == "Eating out copy")
        var renamed = copy
        renamed.name = stored.name
        #expect(renamed.hasSameSettings(as: stored), "Same currency, categories, start, repeat, carry-over and limits")
        #expect(copy.limits.count == 2)
        #expect(Set(copy.limits.map(\.id)).isDisjoint(with: stored.limits.map(\.id)), "The limits are new records")
        let today = F.day(2026, 11, 20)
        #expect(
            try useCases.summary(of: copyID, today: today).current
                == useCases.summary(of: original.id, today: today).current,
            "Its periods and figures match the original's",
        )
        #expect(try repository.budgets().first { $0.id == original.id } == stored, "The original isn't touched")
    }

    @Test("D307.6: the next free name, like the Finder: “copy”, “copy 2”, “copy 3”, compared ignoring case")
    func nextFreeName() throws {
        let original = B.budget()
        let taken = B.budget("EATING OUT COPY", categories: [B.shoppingID])
        let (repository, useCases) = try setup([original, taken])
        _ = try useCases.duplicatedChange(of: original.id, naming: Self.copyName)
        _ = try useCases.duplicatedChange(of: original.id, naming: Self.copyName)
        #expect(
            try repository.budgets().map(\.name).sorted()
                == ["EATING OUT COPY", "Eating out", "Eating out copy 2", "Eating out copy 3"]
        )
    }

    @Test("D307.8: Undo Duplicate Budget deletes the copy; Redo puts it back with the same ID")
    func undoRedo() throws {
        let original = B.budget()
        let (repository, useCases) = try setup([original])
        let change = try useCases.duplicatedChange(of: original.id, naming: Self.copyName)
        let copy = try #require(try repository.budgets().first { $0.id == change.budgetID })

        let undo = try useCases.revert(change, expecting: try useCases.outcome(of: change))
        guard case .reverted(let redo, let redoOutcome) = undo else {
            Issue.record("Undo didn't revert: \(undo)")
            return
        }
        #expect(try repository.budgets().map(\.id) == [original.id])

        let again = try useCases.revert(redo, expecting: redoOutcome)
        guard case .reverted = again else {
            Issue.record("Redo didn't revert: \(again)")
            return
        }
        #expect(try repository.budgets().first { $0.id == copy.id }?.hasSameSettings(as: copy) == true)
    }

    @Test("D310.1: Redo Duplicate Budget when another budget took the copy's name is stale, and writes nothing")
    func redoNameTaken() throws {
        let original = B.budget()
        let (repository, useCases) = try setup([original])
        let change = try useCases.duplicatedChange(of: original.id, naming: Self.copyName)
        let undo = try useCases.revert(change, expecting: try useCases.outcome(of: change))
        guard case .reverted(let redo, let redoOutcome) = undo else {
            Issue.record("Undo didn't revert: \(undo)")
            return
        }
        try repository.saveBudget(B.budget("eating out COPY", categories: [B.shoppingID]))
        let before = repository.snapshot
        #expect(try useCases.revert(redo, expecting: redoOutcome) == .stale(.nameTaken("eating out COPY")))
        #expect(repository.snapshot == before)
    }

    @Test("A budget with no categories left can't be duplicated, as it can't be saved (D307.5)")
    func noCategories() throws {
        let original = B.budget(categories: [B.travelID])
        let (repository, useCases) = try setup([original])
        try repository.deletingCategory(B.travelID)
        let before = repository.snapshot
        #expect(throws: LedgerValidationError.budgetCategoriesRequired) {
            try useCases.duplicatedChange(of: original.id, naming: Self.copyName)
        }
        #expect(repository.snapshot == before)
    }

    @Test("Duplicating a budget that's gone throws missingBudget")
    func missing() throws {
        let (_, useCases) = try setup([])
        #expect(throws: LedgerValidationError.missingBudget) {
            try useCases.duplicatedChange(of: UUID(), naming: Self.copyName)
        }
    }

    // MARK: D313.2: a copy's name always fits

    /// Duplicates a budget named `name` and returns the copy's name.
    private func copyName(of name: String, taken: [String] = []) throws -> String {
        let original = B.budget(name)
        let others = taken.map { B.budget($0, categories: [B.shoppingID]) }
        let (repository, useCases) = try setup([original] + others)
        let change = try useCases.duplicatedChange(of: original.id, naming: Self.copyName)
        return try #require(try repository.budgets().first { $0.id == change.budgetID }).name
    }

    @Test("D313.2: a 98-character name keeps its first 95 characters, then “ copy”, and saves")
    func longNameFits() throws {
        let name = String(repeating: "a", count: 98)
        let copy = try copyName(of: name)
        #expect(copy == String(repeating: "a", count: 95) + " copy")
        #expect(copy.count == 100)
    }

    @Test("D313.2: a 100-character name is shortened for “ copy 2” too, never failing as too long")
    func longNameNumbered() throws {
        let name = String(repeating: "b", count: 100)
        let first = String(repeating: "b", count: 95) + " copy"
        let copy = try copyName(of: name, taken: [first])
        #expect(copy == String(repeating: "b", count: 93) + " copy 2")
        #expect(copy.count == 100)
    }

    @Test("D313.2: counted in characters as they're seen, so an emoji or accented letter at the cut stays whole")
    func cutKeepsGraphemes() throws {
        let family = "\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        let accented = "e\u{301}"
        let thumb = "\u{1F44D}\u{1F3FD}"
        let first = try copyName(of: String(repeating: "a", count: 94) + family + accented + "zz")
        #expect(first == String(repeating: "a", count: 94) + family + " copy")
        #expect(first.count == 100)
        #expect(first.unicodeScalars.count > 100, "The emoji's scalars all stay")

        let second = try copyName(of: String(repeating: "a", count: 93) + accented + thumb + "bbb")
        #expect(second == String(repeating: "a", count: 93) + accented + thumb + " copy")
        #expect(second.count == 100)
    }

    @Test("D313.2: a space left at the cut is trimmed before “ copy”")
    func cutTrimsSpaces() throws {
        let copy = try copyName(of: String(repeating: "c", count: 93) + "  dddd")
        #expect(copy == String(repeating: "c", count: 93) + " copy")
    }

    @Test("A short name isn't shortened")
    func shortNameKept() throws {
        #expect(try copyName(of: "Eating out") == "Eating out copy")
    }
}

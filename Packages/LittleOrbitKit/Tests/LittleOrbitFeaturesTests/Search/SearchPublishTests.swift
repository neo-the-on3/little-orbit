import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Observation
import Synchronization
import Testing

/// #340: a search step that keeps the same results publishes nothing new, so the list and the macOS table don't
/// redraw and diff every row; a step that changes them still does. Observation skips setting a value equal to the
/// one it has, and these pin that for the rows the screens read. All names and amounts are made up.
@MainActor
@Suite("Search publishes only changes")
struct SearchPublishTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    /// Raised from `withObservationTracking`'s change handler.
    final class Flag: Sendable {
        private let state = Mutex(false)

        var raised: Bool { state.withLock { $0 } }

        func raise() {
            state.withLock { $0 = true }
        }
    }

    private func model() -> TransactionSearchViewModel {
        TransactionSearchViewModel(
            search: SearchScreenSpeedTests.Store(SearchScreenSpeedTests.snapshot()),
            updates: LedgerUpdates(),
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            defaultCurrency: "INR",
        )
    }

    /// Whether `step` changes the rows the list or the table read.
    private func rowsChange(_ model: TransactionSearchViewModel, _ step: () -> Void) -> Bool {
        let flag = Flag()
        withObservationTracking {
            _ = (model.sections, model.tableSections, model.tableRows)
        } onChange: {
            flag.raise()
        }
        step()
        return flag.raised
    }

    @Test("“coff” to “coffe” finds the same rows, so the list and table aren't set again")
    func sameResultsPublishNothing() {
        let model = model()
        model.load()
        model.query = "coff"
        model.load()
        let rows = model.sections.flatMap(\.rows).count
        #expect(rows > 0)
        let changed = rowsChange(model) {
            model.query = "coffe"
            model.load()
        }
        #expect(!changed, "Same results, nothing to redraw")
        #expect(model.sections.flatMap(\.rows).count == rows)
        #expect(model.searchedText == "coffe", "The searched text still follows the field")
    }

    @Test("A step that changes the results still updates the list and the table")
    func changedResultsPublish() {
        let model = model()
        model.load()
        model.query = "coffee"
        model.load()
        let changed = rowsChange(model) {
            model.query = "zzzz"
            model.load()
        }
        #expect(changed)
        #expect(model.sections.isEmpty && model.tableSections.isEmpty && model.isNoResults)
        let back = rowsChange(model) { model.clear() }
        #expect(back)
        #expect(model.summary?.countText == "10,000 results")
    }

    @Test("Choosing the sort the table already has doesn't set its rows again; another sort does")
    func sameSortPublishesNothing() {
        let model = model()
        model.load()
        let same = rowsChange(model) { model.sortOrder = [KeyPathComparator(\.date, order: .reverse)] }
        #expect(!same)
        let other = rowsChange(model) { model.sortOrder = [KeyPathComparator(\.amount, order: .forward)] }
        #expect(other)
        #expect(model.tableRows.count == SearchScreenSpeedTests.transactionCount && model.tableSections.isEmpty)
    }
}

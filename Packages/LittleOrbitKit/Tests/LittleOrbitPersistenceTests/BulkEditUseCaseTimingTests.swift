import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// #285, D398: the Bulk Edit of 3,334 of 10,000 rows through the use cases on the in-memory store, Linux CI
/// included: Apply, Undo and Redo each within 2.0 s x `TimingScale`. The SwiftData store's run is in
/// `SwiftDataWriteTimingTests+BulkEditUseCase.swift`.
@MainActor
@Suite("Bulk edit use case timing (#285)", .serialized)
struct BulkEditUseCaseTimingTests {
    typealias T = BulkEditUseCaseTiming  // swiftlint:disable:this type_name

    @Test("Apply, Undo and Redo of 3,334 of 10,000 rows each within 2.0 s (D398)")
    func inMemory() throws {
        let repository = InMemoryLedgerRepository(now: { Date(timeIntervalSince1970: 1_800_000_000) })
        try repository.replaceLedger(with: T.ledger())
        let timing = try T.run(on: repository)
        print(
            "In-memory timing: bulk edit use case of \(timing.selected) in \(T.existing): "
                + "apply \(timing.apply), undo \(timing.undo), redo \(timing.redo)"
        )
        #expect(timing.selected == T.selected)
        #expect(timing.details[0] == ["Bulk edit"])
        #expect(!timing.details[1].contains("Bulk edit"))
        #expect(timing.details[1].count == T.selected)
        #expect(timing.details[2] == ["Bulk edit"])
        try TimingScale.expect("bulk edit use case: apply", timing.apply, under: T.bound)
        try TimingScale.expect("bulk edit use case: undo", timing.undo, under: T.bound)
        try TimingScale.expect("bulk edit use case: redo", timing.redo, under: T.bound)
    }
}

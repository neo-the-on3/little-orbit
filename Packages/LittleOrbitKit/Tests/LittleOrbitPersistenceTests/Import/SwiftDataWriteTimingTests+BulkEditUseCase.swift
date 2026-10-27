#if canImport(SwiftData) && os(macOS)
    import Foundation
    import LittleOrbitDomain
    import Testing

    @testable import LittleOrbitPersistence

    /// #285, D398: Tester2's N5 Bulk Edit (3,334 of 10,000, 6434969976) through the use cases on a real store file,
    /// reopened as at launch: the rows checked with every rule off the main actor, then one write each for Apply,
    /// Undo and Redo, each within 2.0 s x `TimingScale`.
    extension SwiftDataWriteTimingTests {
        @Test("A Bulk Edit of 3,334 of 10,000 rows through the use cases, undone and redone, each within 2.0 s (D398)")
        func bulkEditUseCase() throws {
            let folder = try Self.folder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let seeding = try LittleOrbitStore.makeRepository(configuration: Self.configuration(in: folder))
            try seeding.replaceLedger(with: BulkEditUseCaseTiming.ledger())
            let repository = try LittleOrbitStore.makeRepository(configuration: Self.configuration(in: folder))
            #expect(try repository.transactions().count == BulkEditUseCaseTiming.existing)
            let timing = try BulkEditUseCaseTiming.run(on: repository)
            print(
                "SwiftData timing: bulk edit use case of \(timing.selected) in \(BulkEditUseCaseTiming.existing): "
                    + "apply \(timing.apply), undo \(timing.undo), redo \(timing.redo)"
            )
            #expect(timing.selected == BulkEditUseCaseTiming.selected)
            #expect(timing.details[0] == ["Bulk edit"])
            #expect(timing.details[2] == ["Bulk edit"])
            let bound = BulkEditUseCaseTiming.bound
            try TimingScale.expect("bulk edit use case: apply", timing.apply, under: bound)
            try TimingScale.expect("bulk edit use case: undo", timing.undo, under: bound)
            try TimingScale.expect("bulk edit use case: redo", timing.redo, under: bound)
        }
    }
#endif

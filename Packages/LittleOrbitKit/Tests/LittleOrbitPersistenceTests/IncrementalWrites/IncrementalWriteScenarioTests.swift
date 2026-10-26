import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// #235: every scenario the SwiftData store's incremental write is compared with the whole-store write on runs
/// as written on the in-memory store too, so a scenario that no longer applies fails on every platform. None of
/// them needs the whole-store path, so on SwiftData each is an incremental write.
@Suite("Incremental write scenarios on the in-memory store (#235)")
@MainActor
struct IncrementalWriteScenarioTests {
    @Test("Each scenario runs and changes the ledger", arguments: IncrementalWriteScenario.allCases)
    func scenario(_ scenario: IncrementalWriteScenario) throws {
        let repository = InMemoryLedgerRepository()
        let fixture = try IncrementalWriteFixture.seed(into: repository)
        #expect(
            try repository.attachments(for: fixture.groceries.id).map(\.data) == [IncrementalWriteFixture.receiptBytes]
        )
        var before: LedgerSnapshot?
        try scenario.run(on: repository, fixture) { change in
            before = try repository.ledgerSnapshot()
            try change()
        }
        let start = try #require(before)
        let end = try repository.ledgerSnapshot()
        #expect(end != start)
        #expect(LedgerWriteSet(from: start, to: end).wholeStoreReason == nil)
    }

    /// Linux side of the SwiftData N2 tests: the domain never hands the writer a byteless attachment, so those
    /// tests build the ledger themselves, and each lands on the write path it is meant to cover.
    @Test("A byteless new attachment gets past the domain only as a built ledger, on either write path (N2)")
    func bytelessAttachment() throws {
        let repository = InMemoryLedgerRepository()
        let fixture = try IncrementalWriteFixture.seed(into: repository)
        let start = try repository.ledgerSnapshot()
        let ticket = fixture.bytelessTicket()
        try repository.saveAttachment(ticket)
        #expect(try repository.attachments(for: fixture.movie.id).map(\.byteSize) == [0])

        var target = start
        target.attachments.append(ticket)
        let changes = LedgerWriteSet(from: start, to: target)
        #expect(changes.wholeStoreReason == nil)
        #expect(changes.attachments.upserted == [ticket])
        target.tags.append(try #require(start.tags.first))
        #expect(LedgerWriteSet(from: start, to: target).wholeStoreReason == .duplicateIDs)
    }
}

import Foundation
import Testing

@testable import LittleOrbitDomain

/// D378: a watch Pay or Skip the iPhone refuses for good is final. Nothing is recorded, it leaves the queue, it's
/// answered `refused` so the watch clears its mark, and one notice is queued. Only temporary failures retry.
@MainActor
@Suite("Watch requests the iPhone refuses for good")
struct WatchRequestRefusalTests {
    typealias Fixture = ScheduledFixture
    typealias Scene = WatchPhoneUseCasesTests.Scene

    @Test("A ledger validation error is permanent; a store or unknown error is temporary")
    func classification() {
        #expect(WatchRequestFailure(LedgerValidationError.missingCategory) == .permanent)
        #expect(WatchRequestFailure(LedgerValidationError.categoryKindMismatch) == .permanent)
        #expect(WatchRequestFailure(FlakyScheduleRepository.SaveFailed()) == .temporary)
        #expect(WatchRequestFailure(CocoaError(.fileWriteOutOfSpace)) == .temporary)
    }

    @Test("A Pay the ledger refuses (its category is gone): final, nothing recorded, not kept, one notice")
    func refusedPayIsFinal() throws {
        let scene = try Scene()
        let request = scene.request(.pay, day: 20)
        let categoryID = try #require(scene.plan.categoryID)
        scene.repository.base.snapshot.categories.removeAll { $0.id == categoryID }
        let run = scene.useCases.receive(request)
        #expect(run.outcomes == [WatchRequestOutcome(requestID: request.id, result: .refused)])
        #expect(run.refusedCount == 1 && run.failedCount == 0 && run.queuedNotices == 1 && !run.changedLedger)
        #expect(scene.posted.isEmpty && scene.outcome(on: 20) == nil)
        #expect(scene.inbox.keptRequests().isEmpty)
        #expect(
            scene.useCases.pendingNotices().map(\.notice) == [
                WatchRequestNotice(id: request.id, reason: .refusedOnSave, action: .pay, itemID: scene.plan.id)
            ]
        )
        #expect(scene.useCases.pendingNotices().first?.item?.details == "Rent")
        // The watch hears it in the next snapshot.
        #expect(
            try scene.useCases.snapshot().outcomes.last == WatchRequestOutcome(requestID: request.id, result: .refused)
        )
        // Not tried again at the next activation, and delivered again it's answered the same with no second notice.
        let retry = scene.useCases.applyKept()
        #expect(retry.outcomes.isEmpty && retry.refusedCount == 0)
        let again = scene.useCases.receive(request)
        #expect(again.outcomes.last?.result == .refused && again.queuedNotices == 0)
        #expect(scene.inbox.notices().count == 1 && scene.posted.isEmpty)
    }

    @Test("A refused Skip: final, nothing skipped, one Skip notice")
    func refusedSkipIsFinal() throws {
        let scene = try Scene()
        scene.repository.refuseSettle = .categoryKindMismatch
        let request = scene.request(.skip, day: 20)
        #expect(scene.useCases.receive(request).outcomes.last?.result == .refused)
        #expect(scene.outcome(on: 20) == nil && scene.inbox.keptRequests().isEmpty)
        #expect(scene.inbox.notices().map(\.reason) == [.refusedOnSave])
        #expect(scene.inbox.notices().map(\.action) == [.skip])
    }

    @Test("A temporary failure still retries: kept, no notice, no answer, then applied once")
    func temporaryFailureRetries() throws {
        let scene = try Scene()
        scene.repository.failNextSettle = true
        let request = scene.request(.pay, day: 20)
        let first = scene.useCases.receive(request)
        #expect(first.failedCount == 1 && first.refusedCount == 0 && first.outcomes.isEmpty)
        #expect(scene.inbox.keptRequests() == [request] && scene.inbox.notices().isEmpty)
        #expect(try scene.useCases.snapshot().outcomes.isEmpty)
        #expect(scene.useCases.applyKept().outcomes.last?.result == .applied)
        #expect(scene.posted.count == 1 && scene.inbox.notices().isEmpty)
    }

    @Test("A refused request doesn’t hold up later ones")
    func refusalDoesntBlockOthers() throws {
        let scene = try Scene()
        scene.repository.refuseSettle = .missingCategory
        let refused = scene.request(.pay, day: 20)
        scene.useCases.receive(refused)
        scene.repository.refuseSettle = nil
        let skip = scene.request(.skip, day: 20, month: 9)
        #expect(scene.useCases.receive(skip).outcomes.last?.result == .applied)
        #expect(scene.inbox.keptRequests().isEmpty)
    }

    @Test("A refused notice goes when its item is deleted afterwards")
    func refusedNoticeOfDeletedItemDrops() throws {
        let scene = try Scene()
        scene.repository.refuseSettle = .missingCategory
        scene.useCases.receive(scene.request(.pay, day: 20))
        try scene.repository.deleteScheduledItem(id: scene.plan.id)
        #expect(scene.useCases.pendingNotices().isEmpty && scene.inbox.notices().isEmpty)
    }
}

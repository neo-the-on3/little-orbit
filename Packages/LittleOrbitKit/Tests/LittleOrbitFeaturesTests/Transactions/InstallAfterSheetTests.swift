import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tester2's D405 on 3dc318b (comment 6448338326): the Undo pause still had a 0.36–0.47 s freeze with the sheet up,
/// from the install to the sheet's dismissal turn. The install swaps the main context, and the old one is torn down
/// on the main queue after it. Now a save off the main actor installs only once the sheet has gone. Made-up data.
@MainActor
@Suite("A batch Undo or Redo installs its save after its sheet has gone", .timeLimit(.minutes(1)))
struct InstallAfterSheetTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @Test(
        "Saved off the main actor: the ledger in memory is unchanged until the sheet has gone",
        arguments: [false, true],
    )
    func installAfterSheet(redo: Bool) async throws {
        let count = BatchSheetPolicy.rowsThatShowSheet
        let rows = (0..<count)
            .map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 1).addingTimeInterval(Double($0) * 60)) }
        let memory = try F.repository(rows)
        memory.offMainSave = {}
        let useCases = TransactionUseCases(repository: memory, categoryNames: CatalogDefaultCategoryNames())
        let window = TestWindow(useCases)
        window.history.setScreen(.account(F.savingsID))
        var changes = BulkEditChanges()
        changes.details = .some("Bulk")
        let request = BulkEditRequest(
            selection: rows,
            changes: changes,
            payeeName: "",
            accounts: try memory.accounts(),
            timeZoneID: F.zoneID,
            now: F.now,
        )
        let change = try await useCases.bulkEdit.apply(request, reporting: .silent)
        window.history.record(change)
        window.history.markBulkEdit(change)
        let first = rows[0].id
        func details() throws -> String? { try memory.transactions().first { $0.id == first }?.details }

        let sleeper = ManualSleeper()
        if redo {
            try await Self.run(window, redo: false, sleeper)
        }
        let before = try details()
        let revision = memory.revision
        if redo {
            window.history.redo()
        } else {
            window.history.undo()
        }
        window.history.batchProgress?.sleep = sleeper.sleep
        await RealTime.eventually { window.history.batchProgress == nil }
        // Saved, and the sheet is closing: nothing is installed yet.
        try #require(window.history.closingProgress?.isShown == true)
        #expect(try details() == before, "Not installed while the sheet is up")
        #expect(memory.revision == revision)
        #expect(window.history.isBatchRunning)

        window.history.batchSheetDismissed()
        try await Self.untilSettle(sleeper)
        #expect(try details() == before, "Not installed while the sheet finishes closing")
        await sleeper.advance()
        await RealTime.eventually { !window.history.isBatchRunning && window.history.batchRun == nil }
        #expect(try details() == (redo ? "Bulk" : rows[0].details), "Installed once the sheet had gone")
        #expect(memory.revision != revision)
        #expect(window.announcements.last?.hasPrefix(redo ? "Redid" : "Undid") == true)
    }

    /// An Undo or Redo through to its end, its sheet dismissed when asked.
    private static func run(_ window: TestWindow, redo: Bool, _ sleeper: ManualSleeper) async throws {
        if redo {
            window.history.redo()
        } else {
            window.history.undo()
        }
        window.history.batchProgress?.sleep = sleeper.sleep
        await RealTime.eventually { window.history.batchProgress == nil }
        window.history.batchSheetDismissed()
        try await Self.untilSettle(sleeper)
        try #require(await sleeper.advance() == BatchProgress.dismissSettle)
        await RealTime.eventually { !window.history.isBatchRunning && window.history.batchRun == nil }
    }

    /// Steps the dismissal's turn until only its `dismissSettle` waits. The fallback's first turn may be asked for
    /// too, before the dismissal cancels it, and a cancelled sleep leaves only after a hop; stepping it changes
    /// nothing. Real time bounds the wait, as counted turns run out under a loaded parallel run.
    private static func untilSettle(_ sleeper: ManualSleeper) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(RealTime.hangGuard)
        while sleeper.waiting != [BatchProgress.dismissSettle], clock.now < deadline {
            if sleeper.waiting.first == BatchProgress.uiTurnLength {
                await sleeper.advance()
            } else {
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        try #require(sleeper.waiting == [BatchProgress.dismissSettle], "\(sleeper.waiting)")
    }
}

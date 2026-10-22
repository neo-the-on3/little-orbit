import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D195.5 and L11–L14: the Keep steppers, the 'Delete N Backups?' alert, App Lock and the cleanup.
@MainActor
@Suite("Backups view model: Keep", .timeLimit(.minutes(2)))
struct BackupsRetentionViewModelTests {
    /// The harness with `count` automatic backups, one a day from 23 Oct.
    private func harness(backups count: Int) async throws -> BackupHarness {
        let harness = try BackupHarness()
        for day in 0..<count {
            harness.advance(86_400)
            try harness.repository.saveAccount(
                Account(
                    name: "Day \(day)",
                    type: .cash,
                    currencyCode: "INR",
                    openingBalance: 1,
                    sortOrder: Double(10 + day),
                )
            )
            _ = try await harness.service.backUpAutomaticallyIfNeeded()
        }
        return harness
    }

    @Test("The steppers start at 7 and 12 with the L11 footer")
    func defaults() async throws {
        let harness = try await harness(backups: 0)
        let model = harness.viewModel()
        try await model.load()
        #expect(model.retention == .default)
        #expect(model.keepFooter.hasPrefix("little-orbit keeps your 7 most recent automatic backups and the first"))
        #expect(model.retentionEnabled)
    }

    @Test("Lowering N asks first with the exact count, then App Lock, then deletes exactly those (L12, L13)")
    func lowerAndConfirm() async throws {
        let harness = try await harness(backups: 8)
        let lock = RecordingAuthentication(allows: true)
        let model = harness.viewModel(authentication: lock)
        try await model.load()
        let proposed = BackupRetention(recentAutomatic: 3, monthlyMonths: 12)
        let prompt = try #require(try await model.proposeRetention(proposed))
        #expect(prompt.title == "Delete 4 Backups?")
        #expect(prompt.confirmTitle == "Delete 4 Backups")
        #expect(prompt.plan.retention == proposed)
        #expect(model.rows.count == 8)
        #expect(lock.purposes.isEmpty)
        // Nothing is saved before the answer, so another window still shows 7.
        #expect(model.retention == .default)
        #expect(harness.settings.retention() == .default)

        try await model.confirmPrune(prompt)
        #expect(lock.purposes == [.pruneBackups])
        #expect(model.rows.count == 4)
        #expect(model.retention.recentAutomatic == 3)
        #expect(harness.settings.retention().recentAutomatic == 3)
        #expect(model.keepFooter.hasPrefix("little-orbit keeps your 3 most recent"))
    }

    @Test("Cancel, or cancelling App Lock, puts the setting back and deletes nothing (L13)")
    func cancel() async throws {
        let harness = try await harness(backups: 8)
        let lock = RecordingAuthentication(allows: false)
        let model = harness.viewModel(authentication: lock)
        try await model.load()

        // Cancel is the window dropping its prompt: nothing was saved or deleted.
        let first = try #require(
            try await model.proposeRetention(BackupRetention(recentAutomatic: 6, monthlyMonths: 12))
        )
        #expect(first.title == "Delete 1 Backup?")
        #expect(model.retention == .default)
        #expect(model.rows.count == 8)

        let second = try #require(
            try await model.proposeRetention(BackupRetention(recentAutomatic: 7, monthlyMonths: 0))
        )
        try await model.confirmPrune(second)
        #expect(lock.purposes == [.pruneBackups])
        #expect(model.retention == .default)
        #expect(harness.settings.retention() == .default)
        #expect(model.rows.count == 8)
    }

    @Test("Raising, or lowering when nothing would go, saves with no alert (L14)")
    func noAlert() async throws {
        let harness = try await harness(backups: 3)
        let model = harness.viewModel()
        try await model.load()
        #expect(try await model.proposeRetention(BackupRetention(recentAutomatic: 10, monthlyMonths: 12)) == nil)
        #expect(harness.settings.retention().recentAutomatic == 10)
        #expect(model.retention.recentAutomatic == 10)
        #expect(try await model.proposeRetention(BackupRetention(recentAutomatic: 10, monthlyMonths: 11)) == nil)
        #expect(harness.settings.retention().monthlyMonths == 11)
        #expect(try await model.proposeRetention(BackupRetention(recentAutomatic: 3, monthlyMonths: 11)) == nil)
        #expect(harness.settings.retention().recentAutomatic == 3)
        #expect(model.rows.count == 3)
    }

    @Test("The steppers are off while a backup runs (L14, D118.5)")
    func disabledWhileBackingUp() async throws {
        let harness = try await harness(backups: 0)
        let model = harness.viewModel()
        try await model.load()
        var enabledDuring: Bool?
        let task = Task { try? await model.backUpNow() }
        await Task.yield()
        enabledDuring = model.retentionEnabled
        await task.value
        #expect(enabledDuring == false)
        #expect(model.retentionEnabled)
    }

    @Test("Two windows on one model: one window's prompt changes nothing the other shows (Tech Architect)")
    func promptIsPerWindow() async throws {
        let harness = try await harness(backups: 8)
        let model = harness.viewModel()
        let first = BackupsWindow(model: model)
        let second = BackupsWindow(model: model)
        await first.load()
        await first.proposeRetention(BackupRetention(recentAutomatic: 3, monthlyMonths: 12))
        let prompt = try #require(first.prunePrompt)
        #expect(first.shownRetention.recentAutomatic == 3)
        #expect(!first.retentionEnabled)
        // The other window still sees the saved values, footer and every backup, and can use its steppers.
        #expect(second.prunePrompt == nil)
        #expect(second.shownRetention == .default)
        #expect(model.keepFooter.hasPrefix("little-orbit keeps your 7 most recent"))
        #expect(second.retentionEnabled)
        #expect(model.rows.count == 8)
        await first.confirmPrune(prompt)
        #expect(first.prunePrompt == nil)
        #expect(second.prunePrompt == nil)
        #expect(model.retention.recentAutomatic == 3)
    }
}

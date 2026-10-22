import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// Background time as UIKit gives it: each `begin` gets a new ID, and the test runs out the time with `expire()`.
@MainActor
final class FakeBackgroundActivity: BackgroundActivity {
    private(set) var begun: [String] = []
    private(set) var ended: [BackgroundActivityID] = []
    private var handlers: [BackgroundActivityID: @MainActor () -> Void] = [:]

    func begin(_ name: String, expired: @escaping @MainActor () -> Void) -> BackgroundActivityID? {
        begun.append(name)
        let id = BackgroundActivityID(rawValue: begun.count)
        handlers[id] = expired
        return id
    }

    func end(_ id: BackgroundActivityID) {
        ended.append(id)
        handlers[id] = nil
    }

    /// The system's expiry: every activity still running is told its time is up.
    func expire() {
        for handler in handlers.values {
            handler()
        }
    }
}

/// The backup when the app goes to the background runs inside a background-time assertion, and is cancelled
/// cleanly when the time runs out: no folder, nothing in the staging folder, no failure line (Tech Architect).
@MainActor
@Suite("Background backup")
struct BackgroundBackupTests {
    private static let size = BackupChunk.size * 5 / 2

    /// Waits, a little at a time, until `condition` holds.
    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<2_000 where !condition() {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(condition())
    }

    @Test("The backup runs inside one assertion, ended once when it's done")
    func completes() async throws {
        let fixture = try StreamingFixture(size: 10)
        let model = fixture.harness.viewModel()
        let activity = FakeBackgroundActivity()

        await model.backUpInBackground(activity)?.value

        #expect(activity.begun == ["Automatic backup"])
        #expect(activity.ended == [BackgroundActivityID(rawValue: 1)])
        #expect(try await fixture.harness.service.overview().backups.map(\.kind) == [.automatic])
    }

    @Test("When the time runs out mid-write, the backup is cancelled: no folder, staging empty, no failure line")
    func expiryCancels() async throws {
        let fixture = try StreamingFixture(size: Self.size)
        let model = fixture.harness.viewModel()
        let activity = FakeBackgroundActivity()
        // Both attachments are hashed first; the first write then waits here.
        fixture.source.hooks.gate(3)

        let task = model.backUpInBackground(activity)
        try await wait { fixture.source.hooks.hasReachedGate }
        #expect(!fixture.stagingIsEmpty)
        // One at a time: going to the background again meanwhile starts nothing.
        #expect(model.backUpInBackground(activity) == nil)
        #expect(activity.begun.count == 1)

        activity.expire()
        #expect(activity.ended == [BackgroundActivityID(rawValue: 1)])
        fixture.source.hooks.release()
        await task?.value

        #expect(activity.ended == [BackgroundActivityID(rawValue: 1)])
        #expect(fixture.folders.isEmpty)
        #expect(fixture.stagingIsEmpty)
        let overview = try await fixture.harness.service.overview()
        #expect(overview.backups.isEmpty)
        #expect(overview.lastFailure == nil)
        #expect(!model.isBackingUp)
        #expect(model.failureMessage == nil)

        // The next time it runs, the backup is made.
        await model.backUpInBackground(activity)?.value
        #expect(try await fixture.harness.service.overview().backups.map(\.kind) == [.automatic])
    }

    @Test("Time running out while the attachments are hashed stops before anything is written")
    func expiryWhileHashing() async throws {
        let fixture = try StreamingFixture(size: Self.size)
        let model = fixture.harness.viewModel()
        let activity = FakeBackgroundActivity()
        fixture.source.hooks.gate(1)

        let task = model.backUpInBackground(activity)
        try await wait { fixture.source.hooks.hasReachedGate }
        activity.expire()
        fixture.source.hooks.release()
        await task?.value

        #expect(fixture.source.hooks.calls == 1)
        #expect(fixture.folders.isEmpty)
        #expect(fixture.stagingIsEmpty)
    }

    @Test("Without background time, on macOS, the backup still runs")
    func withoutActivity() async throws {
        let fixture = try StreamingFixture(size: 10)
        let model = fixture.harness.viewModel()
        await model.backUpInBackground(nil)?.value
        #expect(try await fixture.harness.service.overview().backups.count == 1)
    }
}

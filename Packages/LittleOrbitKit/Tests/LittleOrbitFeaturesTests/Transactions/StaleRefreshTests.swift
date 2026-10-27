import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tech Architect's review of #286 (N5): a register refresh that finishes after a newer one never shows over it.
/// Each refresh's off-main build is held until the test finishes it, so completions come in the test's order.
@MainActor
@Suite("Register refresh: the newest one shows")
struct StaleRefreshTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private static func register(_ builds: HeldBuilds) throws -> (AccountHistoryViewModel, LedgerUpdates) {
        let lunch = F.expense(250, on: F.date(2026, 10, 19), account: F.cardID, details: "Lunch")
        let useCases = TransactionUseCases(
            repository: try F.repository([lunch]),
            categoryNames: CatalogDefaultCategoryNames(),
        )
        let updates = LedgerUpdates()
        let model = AccountHistoryViewModel(
            useCases: useCases,
            accountID: F.cardID,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        model.buildContent = builds.builder
        model.seenRevision = updates.revision
        model.load()
        return (model, updates)
    }

    @Test("An older refresh that finishes after a newer one is dropped; the newer one's rows stay")
    func olderFinishesLast() async throws {
        let builds = HeldBuilds()
        let (model, updates) = try Self.register(builds)
        updates.changed()
        let older = Task { await model.refresh(after: updates) }
        let olderBuild = await builds.next()
        updates.changed()
        let newer = Task { await model.refresh(after: updates) }
        let newerBuild = await builds.next()

        newerBuild.finish(balance: "newer")
        await newer.value
        #expect(model.balanceText == "newer")
        olderBuild.finish(balance: "older")
        await older.value
        #expect(model.balanceText == "newer", "The older result finished last and is dropped")
        #expect(model.seenRevision == updates.revision)
    }

    @Test("A refresh with no newer one shows its result")
    func onlyRefresh() async throws {
        let builds = HeldBuilds()
        let (model, updates) = try Self.register(builds)
        #expect(model.balanceText != "only")
        updates.changed()
        let refresh = Task { await model.refresh(after: updates) }
        await builds.next().finish(balance: "only")
        await refresh.value
        #expect(model.balanceText == "only")
    }
}

/// Hands each refresh's build to the test, which finishes it with a balance text that marks whose result shows.
@MainActor
private final class HeldBuilds {
    private var started: [HeldBuild] = []
    private var waiting: [CheckedContinuation<HeldBuild, Never>] = []

    nonisolated var builder: AccountHistoryContentBuilder {
        { _, _, _, _ in await self.hold() }
    }

    /// The next build a refresh started, in the order they started.
    func next() async -> HeldBuild {
        if !started.isEmpty {
            return started.removeFirst()
        }
        return await withCheckedContinuation { waiting.append($0) }
    }

    private func hold() async -> AccountHistoryContent {
        let balance = await withCheckedContinuation { continuation in
            let build = HeldBuild(continuation)
            if waiting.isEmpty {
                started.append(build)
            } else {
                waiting.removeFirst().resume(returning: build)
            }
        }
        return AccountHistoryContent(
            balanceText: balance,
            balanceTone: .neutral,
            afterUpcomingText: nil,
            upcomingTotalText: nil,
            upcoming: [],
            sections: [],
        )
    }
}

@MainActor
private final class HeldBuild {
    private let continuation: CheckedContinuation<String, Never>

    init(_ continuation: CheckedContinuation<String, Never>) {
        self.continuation = continuation
    }

    func finish(balance: String) {
        continuation.resume(returning: balance)
    }
}

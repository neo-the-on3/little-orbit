import Foundation
import Testing

@testable import LittleOrbitFeatures

/// k1 on c6b3778 (Tester2 6442460869), Undo run 4: the announcement fired at +1.41 s while the sheet stayed up
/// until +1.88 s. The 1.5 s fallback counted from the batch's end, and a long main-actor block after it ate the
/// wait. Now it counts from the first free turn of the main actor, when SwiftUI starts the dismissal, and it
/// waits on while the sheet's view is still drawn, up to a safety limit for a sheet that never closes.
@MainActor
@Suite("Batch announcement fallback: never before a closing sheet has closed")
struct BatchAnnouncementFallbackTests {
    /// What was posted, in order.
    final class Heard {
        var texts: [String] = []
    }

    /// A batch whose sheet is up, ended, with its announcement held.
    static func heldAnnouncement(
        _ heard: Heard,
        delay: Duration,
        limit: Duration = .seconds(30),
        drawn: Bool,
    ) async -> BatchProgress {
        let progress = BatchProgress(kind: .undoing, total: 3_334, showAfter: .seconds(60))
        progress.fallbackDelay = delay
        progress.fallbackLimit = limit
        let reporter = progress.start()
        await reporter.reportSaving(3_334, offMain: true)
        if drawn {
            progress.sheetAppeared()
        }
        progress.finish()
        progress.announceAfterSheet("Undid Edit") { heard.texts.append($0) }
        return progress
    }

    /// Keeps the main actor busy, as a long refresh does, without letting anything else run.
    static func blockMainActor(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Waits up to 10 s for something to be heard.
    static func waitForAnnouncement(_ heard: Heard) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        while heard.texts.isEmpty, clock.now - start < .seconds(10) {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("The wait starts once the main actor is free, not when the batch ended")
    func countsFromDismissal() async throws {
        let heard = Heard()
        _ = await Self.heldAnnouncement(heard, delay: .milliseconds(200), drawn: false)
        // The fallback starts, then the main actor stays busy past the whole delay, as the table's update after
        // the batch does.
        await Task.yield()
        Self.blockMainActor(seconds: 0.4)
        try await Task.sleep(for: .milliseconds(100))
        #expect(heard.texts.isEmpty, "The fallback hasn't run out during the block")
        try await Self.waitForAnnouncement(heard)
        #expect(heard.texts == ["Undid Edit"])
    }

    @Test("While the sheet is still drawn the fallback waits; once it closes, it's posted once")
    func waitsForDrawnSheet() async throws {
        let heard = Heard()
        let progress = await Self.heldAnnouncement(heard, delay: .milliseconds(50), drawn: true)
        try await Task.sleep(for: .milliseconds(400))
        #expect(heard.texts.isEmpty, "Not over a sheet that's still closing")
        progress.sheetDisappeared()
        progress.sheetClosed()
        #expect(heard.texts == ["Undid Edit"])
        try await Task.sleep(for: .milliseconds(250))
        #expect(heard.texts == ["Undid Edit"], "Once: the fallback doesn't post again")
    }

    @Test("A drawn sheet that never closes still gets its announcement, at the safety limit")
    func safetyLimit() async throws {
        #expect(BatchProgress.announcementFallbackLimit == .seconds(5))
        let heard = Heard()
        let progress = await Self.heldAnnouncement(
            heard,
            delay: .milliseconds(50),
            limit: .milliseconds(400),
            drawn: true,
        )
        try await Task.sleep(for: .milliseconds(150))
        #expect(heard.texts.isEmpty, "Still waiting for the drawn sheet")
        try await Self.waitForAnnouncement(heard)
        #expect(heard.texts == ["Undid Edit"])
        progress.sheetClosed()
        #expect(heard.texts == ["Undid Edit"], "Once")
    }
}

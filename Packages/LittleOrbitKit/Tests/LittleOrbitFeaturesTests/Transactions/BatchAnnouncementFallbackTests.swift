import Foundation
import Testing

@testable import LittleOrbitFeatures

/// k1 on c6b3778 (Tester2 6442460869), Undo run 4: the announcement fired at +1.41 s while the sheet stayed up
/// until +1.88 s. The 1.5 s fallback counted from the batch's end, and a long main-actor block after it ate the
/// wait. Now it counts from the first free turn of the main actor, when SwiftUI starts the dismissal, and it
/// waits on while the sheet's view is still drawn, up to a safety limit for a sheet that never closes.
///
/// Every wait goes through `ManualSleeper`, so nothing here depends on real time: the safety-limit test failed in
/// 6 of 6 full macOS runs at 8728d1f under parallel load and passed alone (Tester2).
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
        sleeper: ManualSleeper,
        delay: Duration,
        limit: Duration = .seconds(30),
        drawn: Bool,
    ) async -> BatchProgress {
        let progress = BatchProgress(kind: .undoing, total: 3_334, showAfter: nil)
        progress.fallbackDelay = delay
        progress.fallbackLimit = limit
        progress.sleep = sleeper.sleep
        let reporter = progress.start()
        await reporter.reportSaving(3_334, offMain: true)
        reporter.handingOff()
        if drawn {
            progress.sheetAppeared()
        }
        progress.finish()
        progress.announceAfterSheet("Undid Edit") { heard.texts.append($0) }
        return progress
    }

    @Test("The wait starts once the main actor is free, not when the batch ended")
    func countsFromDismissal() async throws {
        let heard = Heard()
        let sleeper = ManualSleeper()
        _ = await Self.heldAnnouncement(heard, sleeper: sleeper, delay: .milliseconds(200), drawn: false)
        // First a turn of the main actor, which a long block after the batch holds up; only then the delay.
        #expect(await sleeper.advance() == BatchProgress.uiTurnLength)
        #expect(await sleeper.next() == .milliseconds(200))
        #expect(heard.texts.isEmpty, "The fallback hasn't run out before its delay")
        await sleeper.advance()
        await ManualSleeper.until { !heard.texts.isEmpty }
        #expect(heard.texts == ["Undid Edit"])
        #expect(sleeper.asked == [BatchProgress.uiTurnLength, .milliseconds(200)])
    }

    @Test("While the sheet is still drawn the fallback waits; once it closes, it's posted once")
    func waitsForDrawnSheet() async throws {
        let heard = Heard()
        let sleeper = ManualSleeper()
        let progress = await Self.heldAnnouncement(heard, sleeper: sleeper, delay: .milliseconds(50), drawn: true)
        await sleeper.advance()
        await sleeper.advance()
        // Past the delay, it rechecks while the sheet's view is on screen.
        for _ in 0..<3 {
            #expect(await sleeper.advance() == BatchProgress.announcementFallbackRecheck)
        }
        #expect(heard.texts.isEmpty, "Not over a sheet that's still closing")
        progress.sheetDisappeared()
        progress.sheetClosed()
        #expect(heard.texts == ["Undid Edit"])
        await ManualSleeper.until(turns: 200) { !sleeper.isWaiting }
        #expect(heard.texts == ["Undid Edit"], "Once: the fallback doesn't post again")
    }

    @Test("A drawn sheet that never closes still gets its announcement, at the safety limit")
    func safetyLimit() async throws {
        #expect(BatchProgress.announcementFallbackLimit == .seconds(5))
        let heard = Heard()
        let sleeper = ManualSleeper()
        let progress = await Self.heldAnnouncement(
            heard,
            sleeper: sleeper,
            delay: .milliseconds(50),
            limit: .milliseconds(400),
            drawn: true,
        )
        await sleeper.advance()
        await sleeper.advance()
        // 50 ms waited; three 100 ms rechecks bring it to 350 ms, still under the limit.
        for _ in 0..<3 {
            await sleeper.advance()
            #expect(heard.texts.isEmpty, "Still waiting for the drawn sheet")
        }
        // The fourth brings it to 450 ms, past the 400 ms limit: posted, with the sheet still drawn.
        #expect(await sleeper.advance() == BatchProgress.announcementFallbackRecheck)
        await ManualSleeper.until { !heard.texts.isEmpty }
        #expect(heard.texts == ["Undid Edit"])
        #expect(!sleeper.isWaiting)
        progress.sheetClosed()
        #expect(heard.texts == ["Undid Edit"], "Once")
    }
}

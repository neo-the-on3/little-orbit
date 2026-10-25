import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// The catch-up hint's wording (D338.1–D338.5, D338.7) and when it shows and goes (D338.6).
@MainActor
@Suite("Scheduled catch-up hint (D338)")
struct ScheduledCatchUpHintTests {
    @Test("D338: the catch-up hint for one item, in every window, until Scheduled is left after showing it")
    func catchUpHint() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, automatic: true)
        try scene.add(rent)
        let feature = scene.feature()
        feature.catchUp(atLaunch: true)
        let list = feature.makeList()
        list.load()
        // The dates are joined in the system list format for the locale ("1 Aug, 1 Sep and 1 Oct" on Apple's en_IN).
        let days = ["1 Aug", "1 Sep", "1 Oct"].formatted(.list(type: .and).locale(Locale(identifier: "en_IN")))
        #expect(
            list.catchUpHint
                == "3 missed automatic Rent transactions were recorded: \(days). Each is recorded only once."
        )
        // A second window reads the same hint; the Mac shows all of it too (D338.7).
        let mac = ScheduledListViewModel(
            useCases: feature.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: .macOS,
        )
        mac.load()
        #expect(mac.catchUpHint == list.catchUpHint)
        // Not on screen yet: leaving keeps it.
        list.dismissCatchUpHint()
        #expect(list.catchUpHint != nil)
        // Loaded on screen but not drawn yet: not shown, so leaving keeps it.
        list.screenAppeared(.list)
        list.load()
        list.dismissCatchUpHint()
        mac.load()
        #expect(mac.catchUpHint != nil)
        // Drawn, then left: it goes, in every window.
        list.load()
        list.catchUpHintAppeared()
        list.dismissCatchUpHint()
        mac.load()
        #expect(list.catchUpHint == nil && mac.catchUpHint == nil)
        // Nothing recorded: no hint.
        feature.catchUp(atLaunch: false)
        list.load()
        #expect(list.catchUpHint == nil)
    }

    @Test("D338.6: unseen, the hint survives other screens and a relaunch, and covers every catch-up until shown")
    func catchUpHintPending() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Rent", day: 1, automatic: true))
        let first = scene.feature()
        first.catchUp(atLaunch: true)
        // Catch-up ran while an item screen was on top: nothing was shown.
        let list = first.makeList()
        list.screenAppeared(.item(UUID()))
        list.load()
        #expect(list.catchUpHint != nil)

        // Relaunched on 2 Nov: the next catch-up merges in.
        scene.now = ScheduledScene.date(CalendarDay(year: 2026, month: 11, day: 2))
        let second = scene.feature()
        second.catchUp(atLaunch: true)
        let relaunched = second.makeList()
        relaunched.load()
        let days = ["1 Aug", "1 Sep", "1 Oct", "1 Nov"].formatted(.list(type: .and).locale(Locale(identifier: "en_IN")))
        #expect(
            relaunched.catchUpHint
                == "4 missed automatic Rent transactions were recorded: \(days). Each is recorded only once."
        )
        // Shown, then the app quits on Scheduled: the next launch doesn't show it again.
        relaunched.screenAppeared(.list)
        relaunched.catchUpHintAppeared()
        let third = scene.feature().makeList()
        third.load()
        #expect(third.catchUpHint == nil)
    }

    @Test("D338.6: a pending hint whose items were all deleted is forgotten once Scheduled is shown")
    func catchUpHintForDeletedItems() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, automatic: true)
        try scene.add(rent)
        let feature = scene.feature()
        feature.catchUp(atLaunch: true)
        try scene.repository.deleteScheduledItem(id: rent.id)
        let list = feature.makeList()
        list.screenAppeared(.list)
        list.load()
        #expect(list.catchUpHint == nil)
        #expect(scene.notices.notice() == nil)
    }

    @Test("D338.1: one transaction, more than 5 dates, two items, three or more items, and the manual sentence")
    func catchUpHintForms() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, automatic: true, month: 10)
        try scene.add(rent)
        let feature = scene.feature()
        feature.catchUp(atLaunch: true)
        let list = feature.makeList()
        list.screenAppeared(.list)
        list.load()
        #expect(list.catchUpHint == "1 missed automatic Rent transaction was recorded: 1 Oct. It’s recorded only once.")
        list.catchUpHintAppeared()
        list.dismissCatchUpHint()

        var water = scene.item("Plant watering", day: 1, automatic: true, month: 10)
        water.repeatRule = .daily
        try scene.add(water, scene.item("Gym", day: 18, month: 10))
        scene.now = ScheduledScene.date(CalendarDay(year: 2026, month: 10, day: 25))
        feature.catchUp(atLaunch: false)
        list.load()
        #expect(
            list.catchUpHint
                == "25 missed automatic Plant watering transactions were recorded, from 1 Oct to 25 Oct. Each is recorded only once. Manual items aren’t recorded for you: each missed one is listed under Overdue."
        )
        list.catchUpHintAppeared()
        list.dismissCatchUpHint()

        scene.now = ScheduledScene.date(CalendarDay(year: 2026, month: 11, day: 2))
        feature.catchUp(atLaunch: true)
        list.load()
        let parts = ["1 for Rent", "8 for Plant watering"]
            .formatted(.list(type: .and).locale(Locale(identifier: "en_IN")))
        #expect(
            list.catchUpHint
                == "9 missed automatic transactions were recorded: \(parts). Each is recorded only once. Manual items aren’t recorded for you: each missed one is listed under Overdue."
        )
        list.catchUpHintAppeared()
        list.dismissCatchUpHint()

        try scene.add(
            scene.item("Salary", day: 3, automatic: true, month: 11),
            scene.item("Gas", day: 4, automatic: true, month: 11),
        )
        scene.now = ScheduledScene.date(CalendarDay(year: 2026, month: 11, day: 5))
        feature.catchUp(atLaunch: false)
        list.load()
        // Plant watering 3–5 Nov, Salary 3 Nov and Gas 4 Nov.
        #expect(
            list.catchUpHint
                == "5 missed automatic transactions were recorded for 3 items. Each is recorded only once. Manual items aren’t recorded for you: each missed one is listed under Overdue."
        )
    }

    @Test(
        "Tester #198 bug: the hint is shown only once drawn, and a disappear and reappear in place keeps it",
        arguments: [ScheduledPlatform.iOS, .macOS],
    )
    func catchUpHintSurvivesReappearing(platform: ScheduledPlatform) async throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Rent", day: 1, automatic: true))
        let feature = scene.feature()
        feature.catchUp(atLaunch: true)
        let list = scene.list(feature, platform: platform)
        // The list view's onAppear: loading on screen doesn't count as showing the hint.
        list.screenAppeared(.list)
        list.load()
        #expect(list.catchUpHint != nil)
        #expect(scene.notices.notice()?.shown == false)
        // The Mac's detail column reports the list disappearing and appearing again before the hint is drawn.
        list.screenDisappeared(.list)
        await Self.settle()
        list.screenAppeared(.list)
        list.load()
        #expect(list.catchUpHint != nil)
        #expect(scene.notices.notice() != nil)
        // The hint row appears: now it's shown.
        list.catchUpHintAppeared()
        #expect(scene.notices.notice()?.shown == true)
        // Re-shown in place after it was drawn: it stays in this list, and the notice is used up.
        list.screenDisappeared(.list)
        await Self.settle()
        list.screenAppeared(.list)
        list.load()
        #expect(list.catchUpHint != nil)
        #expect(scene.notices.notice() == nil)
        // The next visit is a new list, which shows nothing.
        let next = scene.list(feature, platform: platform)
        next.screenAppeared(.list)
        next.load()
        #expect(next.catchUpHint == nil)
    }

    /// Lets the list's deferred "left the Scheduled screens" check run.
    private static func settle() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    @Test("Tech Architect NB 1: a restore clears a pending catch-up hint")
    func restoreClearsTheHint() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Rent", day: 1, automatic: true))
        let feature = scene.feature()
        feature.catchUp(atLaunch: true)
        let list = feature.makeList()
        list.load()
        #expect(list.catchUpHint != nil)
        scene.updates.ledgerReplaced()
        list.load()
        #expect(list.catchUpHint == nil)
        #expect(scene.notices.notice() == nil)
    }

    @Test("NB 3, delta NB 1: an item created after today is reported for the log once per launch, with no data")
    func createdAfterTodayIsLogged() throws {
        let scene = try ScheduledScene()
        // Saved while the device clock read 20 Dec; today is 20 Oct.
        let ahead = CalendarDay(year: 2026, month: 12, day: 20)
        try scene.repository.saveScheduledItem(
            scene.item("Rent", day: 1, automatic: true),
            today: ahead,
            now: ScheduledScene.date(ahead),
        )
        var problems: [ScheduledCatchUpProblem] = []
        let feature = ScheduledFeature(
            useCases: scene.useCases,
            updates: scene.updates,
            locale: Locale(identifier: "en_IN"),
            onCatchUpProblem: { problems.append($0) },
        )
        feature.catchUp(atLaunch: true)
        // Becoming active again, twice, logs nothing more.
        feature.catchUp(atLaunch: false)
        feature.catchUp(atLaunch: false)
        #expect(problems.count == 1)
        if case .createdAfterToday = problems.first {} else { Issue.record("expected createdAfterToday") }
    }

    @Test("Delta NB 3: a restore handler can be removed, and a removed one no longer clears the hint")
    func restoreHandlerRemoval() throws {
        let updates = LedgerUpdates()
        var runs: [String] = []
        let first = updates.onLedgerReplaced { runs.append("first") }
        updates.onLedgerReplaced { runs.append("second") }
        updates.ledgerReplaced()
        updates.removeLedgerReplacedHandler(first)
        updates.removeLedgerReplacedHandler(first)
        updates.ledgerReplaced()
        #expect(runs == ["first", "second", "second"])

        let scene = try ScheduledScene()
        try scene.add(scene.item("Rent", day: 1, automatic: true))
        let feature = scene.feature()
        feature.catchUp(atLaunch: true)
        feature.stopFollowingRestores()
        scene.updates.ledgerReplaced()
        #expect(scene.notices.notice() != nil)
    }
}

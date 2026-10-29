import Foundation
import LittleOrbitFeatures
import Testing

/// One open event gives exactly one import sheet (Tech Architect on #339). The open handlers sit on every main
/// window, so each window that's handed the event posts it here, and only one window takes it: the main window
/// last made key (the frontmost), else the window that posted it, else the first window up, as on a cold launch.
/// File names and window IDs are made up.
@MainActor
@Suite("One import sheet per open event (#189)")
struct ExternalImportEventsTests {
    static let riverstone = [URL(fileURLWithPath: "/tmp/riverstone_oct.csv")]
    static let harbor = [URL(fileURLWithPath: "/tmp/harbor_nov.csv")]

    let first = UUID()
    let second = UUID()
    let third = UUID()

    func threeWindows() -> ExternalImportEvents {
        let events = ExternalImportEvents()
        for window in [first, second, third] {
            events.windowAppeared(window)
        }
        return events
    }

    @Test("Given three windows handed one event, Then only the key window takes it, once")
    func oneSheetPerEvent() {
        let events = threeWindows()
        events.windowBecameKey(second)
        #expect(events.post(Self.riverstone, from: first))
        #expect(!events.post(Self.riverstone, from: second))
        #expect(!events.post(Self.riverstone, from: third))
        #expect(events.receiver == second)
        #expect(events.take(for: first) == nil)
        #expect(events.take(for: third) == nil)
        #expect(events.take(for: second) == Self.riverstone)
        #expect(events.take(for: second) == nil)
        #expect(events.take(for: first) == nil)
        #expect(events.pending == nil)
    }

    @Test("Given the key window moves to another, Then the newest key window takes the event")
    func latestKeyWindowWins() {
        let events = threeWindows()
        events.windowBecameKey(first)
        events.windowBecameKey(third)
        events.post(Self.riverstone, from: first)
        #expect(events.take(for: first) == nil)
        #expect(events.take(for: third) == Self.riverstone)
    }

    @Test("Given no main window has been key, Then the window that was handed the event takes it")
    func posterTakesWithoutKeyWindow() {
        let events = threeWindows()
        events.post(Self.riverstone, from: third)
        #expect(events.receiver == third)
        #expect(events.take(for: first) == nil)
        #expect(events.take(for: third) == Self.riverstone)
    }

    @Test("Given the key window closed, Then the event goes to the window that was handed it")
    func closedKeyWindowPassesOn() {
        let events = threeWindows()
        events.windowBecameKey(second)
        events.windowClosed(second)
        events.post(Self.riverstone, from: first)
        #expect(events.receiver == first)
        #expect(events.take(for: second) == nil)
        #expect(events.take(for: first) == Self.riverstone)
    }

    @Test("Given no window, When a file is opened from the Dock or Finder, Then the new window takes it")
    func coldOpenWaitsForWindow() {
        let events = ExternalImportEvents()
        let new = UUID()
        events.post(Self.riverstone, from: new)
        #expect(events.receiver == nil)
        #expect(events.take(for: new) == nil)
        events.windowAppeared(new)
        #expect(events.receiver == new)
        #expect(events.take(for: new) == Self.riverstone)
    }

    @Test("Given an event posted by no window that's up, Then the first window up takes it")
    func firstWindowUpTakesOrphan() {
        let events = ExternalImportEvents()
        events.post(Self.riverstone, from: UUID())
        events.windowAppeared(first)
        events.windowAppeared(second)
        #expect(events.take(for: second) == nil)
        #expect(events.take(for: first) == Self.riverstone)
    }

    @Test("Given an event waiting, When another file is opened before a window takes it, Then it replaces the first")
    func newerEventReplaces() {
        let events = threeWindows()
        events.post(Self.riverstone, from: first)
        #expect(events.post(Self.harbor, from: first))
        #expect(events.take(for: first) == Self.harbor)
        #expect(events.take(for: first) == nil)
    }

    @Test("Given an event already taken, When the same file is opened again, Then it's a new event")
    func sameFileAgainAfterTake() {
        let events = threeWindows()
        events.post(Self.riverstone, from: first)
        _ = events.take(for: first)
        #expect(events.post(Self.riverstone, from: first))
        #expect(events.take(for: first) == Self.riverstone)
    }

    @Test("The feature keeps one list of open events for every window")
    func sharedByFeature() {
        let feature = ActiveImportsTests.feature()
        feature.externalEvents.windowAppeared(first)
        feature.externalEvents.post(Self.riverstone, from: first)
        #expect(feature.externalEvents.take(for: first) == Self.riverstone)
    }
}

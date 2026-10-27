import Foundation
import LittleOrbitCore

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif

// MARK: A menu opened by a press made during a batch (Tech Architect's m14 on e291012)
//
// A press that opens a menu, made while a batch blocked the main thread, may only be handled once the batch has
// ended and the gate is open: the menu then opens with Undo on, and a release on it would run a command pressed
// during the batch. So when any menu starts tracking, the last left mouse-down is read from the event source, on the
// `systemUptime` clock; inside the batch running now, or the last one, Undo and Redo stay off until that menu closes.
// A reading that can't be right holds nothing (fail open).

extension UndoCommandGate {
    /// What a menu that started tracking did with the gate, for `ledger.editMenu.trackingPress`.
    enum TrackingDecision: Equatable {
        /// The press fell inside a batch: off until the menu closes.
        case held
        /// The press was outside any batch.
        case passed
        /// No reading, or one that can't be right.
        case noReading
    }

    /// When the left mouse button last went down, from `now` and the event source's seconds since: `nil` when the
    /// reading can't be right, not a number, infinite, zero or less, or before the clock's start.
    static func pressTime(now: TimeInterval, secondsSince: Double?) -> TimeInterval? {
        guard let secondsSince, secondsSince.isFinite, secondsSince > 0, now.isFinite, secondsSince <= now else {
            return nil
        }
        return now - secondsSince
    }

    /// A menu started tracking (`NSMenu.didBeginTrackingNotification`): holds Undo and Redo off until it closes when
    /// the press that opened it fell inside the batch running now or the last one. Signposted as
    /// `ledger.editMenu.trackingPress`, tagged `held`, `passed` or `noReading`, with, in order: the press time, the
    /// running batch's start, the last batch's start and end (-1 for each one there's none of), and whether the gate
    /// is closed after (1 or 0).
    @discardableResult
    func menuBeganTracking() -> TrackingDecision {
        let now = uptime()
        let press = Self.pressTime(now: now, secondsSince: secondsSinceLeftMouseDown())
        let decision: TrackingDecision
        if let press {
            let inRunning = batchStart.map { press >= $0 && press <= now } ?? false
            decision = inRunning || lastBatch?.contains(press) == true ? .held : .passed
        } else {
            decision = .noReading
        }
        if decision == .held, !isHeldByMenu {
            hold()
        }
        let tag: StaticString =
            switch decision {
            case .held: "held"
            case .passed: "passed"
            case .noReading: "noReading"
            }
        BatchTrace.event(
            "ledger.editMenu.trackingPress",
            tag,
            values: [
                press ?? -1,
                batchStart ?? -1,
                lastBatch?.lowerBound ?? -1,
                lastBatch?.upperBound ?? -1,
                isClosed ? 1 : 0,
            ],
        )
        return decision
    }

    /// Closes the gate until the menu that's tracking now has closed: the next default-mode turn of the main run
    /// loop, which comes only once tracking has ended.
    private func hold() {
        holdForMenu()
        refreshMenu("heldByMenu")
        nextDefaultModeTurn { [weak self] in self?.openAfterTracking() }
    }

    /// Starts following every menu that starts tracking, the main menu's, SwiftUI's and context menus alike. On the
    /// Mac only.
    func observeMenuTracking() {
        #if canImport(AppKit) && os(macOS)
            guard menuTrackingObservation == nil else {
                return
            }
            menuTrackingObservation = NotificationCenter.default.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main,
            ) { _ in
                MainActor.assumeIsolated {
                    UndoCommandGate.shared.menuBeganTracking()
                }
            }
        #endif
    }

    /// The Mac's event source: seconds since the left mouse button last went down anywhere in the session.
    static func eventSourceSecondsSinceLeftMouseDown() -> Double? {
        #if canImport(AppKit) && os(macOS)
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        #else
            nil
        #endif
    }
}

import Foundation

#if canImport(OSLog)
    import OSLog
#endif

/// Signposts for a Bulk Edit and its Undo and Redo, end to end (#286, N5): subsystem `app.littleorbit`, category
/// `Batch`, for Instruments (xctrace, os_signpost). They split a batch into its build, write, save, notification
/// and each window's recompute. Names and counts only, never a value from the ledger. Free unless recording, and
/// nothing on Linux.
public enum BatchTrace {
    #if canImport(OSLog)
        static let signposter = OSSignposter(subsystem: "app.littleorbit", category: "Batch")
    #endif

    /// `body` inside the interval `name`.
    public static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        #if canImport(OSLog)
            let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
            defer { signposter.endInterval(name, state) }
        #endif
        return try body()
    }

    /// `body` inside the interval `name`, tagged with a count, such as the rows written.
    public static func interval<T>(_ name: StaticString, count: Int, _ body: () throws -> T) rethrows -> T {
        #if canImport(OSLog)
            let state = signposter.beginInterval(name, id: signposter.makeSignpostID(), "\(count)")
            defer { signposter.endInterval(name, state) }
        #else
            _ = count
        #endif
        return try body()
    }

    /// An interval that ends when `end()` is called, for one that spans a suspension or several statements.
    public struct Span {
        #if canImport(OSLog)
            let name: StaticString
            let state: OSSignpostIntervalState
        #endif

        public func end() {
            #if canImport(OSLog)
                BatchTrace.signposter.endInterval(name, state)
            #endif
        }
    }

    /// Starts the interval `name`; call `end()` on the result, usually in a `defer`.
    public static func begin(_ name: StaticString) -> Span {
        #if canImport(OSLog)
            Span(name: name, state: signposter.beginInterval(name, id: signposter.makeSignpostID()))
        #else
            Span()
        #endif
    }

    /// A point in time, such as the progress sheet turning on.
    public static func event(_ name: StaticString) {
        #if canImport(OSLog)
            signposter.emitEvent(name)
        #endif
    }

    /// A point in time with a tag that is a fixed word, such as how a window refreshed (`skip`, `full`).
    public static func event(_ name: StaticString, _ tag: StaticString) {
        #if canImport(OSLog)
            signposter.emitEvent(name, "\(tag.description, privacy: .public)")
        #else
            _ = tag
        #endif
    }

    /// A point in time with a number that isn't from the ledger, such as an event's timestamp in seconds.
    public static func event(_ name: StaticString, value: Double) {
        #if canImport(OSLog)
            signposter.emitEvent(name, "\(value, privacy: .public)")
        #else
            _ = value
        #endif
    }

    /// A point in time with a fixed word and several numbers that aren't from the ledger, such as a decision and the
    /// times it was made from, in one line: the tag, then the values in order, separated by spaces.
    public static func event(_ name: StaticString, _ tag: StaticString, values: [Double]) {
        #if canImport(OSLog)
            let numbers = values.map { String($0) }.joined(separator: " ")
            signposter.emitEvent(name, "\(tag.description, privacy: .public) \(numbers, privacy: .public)")
        #else
            _ = (tag, values)
        #endif
    }

    /// An event `name` whose value is the seconds until the main queue next gets to run: main-thread work already
    /// queued, such as a torn-down context's cleanup, as opposed to idle waiting. Nothing on Linux.
    @MainActor
    public static func mainBacklog(_ name: StaticString) {
        #if canImport(OSLog)
            let start = ContinuousClock.now
            Task { @MainActor in
                let waited = ContinuousClock.now - start
                let seconds = Double(waited.components.seconds) + Double(waited.components.attoseconds) / 1e18
                event(name, value: seconds)
            }
        #endif
    }

    #if canImport(OSLog)
        /// The `untilNextTurn` intervals still open; the next turn ends them all.
        @MainActor private static var openTurns: [Span] = []
    #endif

    /// From now until the main actor's next turn: the SwiftUI update that follows an assignment runs in between.
    @MainActor
    public static func untilNextTurn(_ name: StaticString) {
        #if canImport(OSLog)
            openTurns.append(begin(name))
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    let ending = openTurns
                    openTurns.removeAll()
                    for span in ending {
                        span.end()
                    }
                }
            }
        #endif
    }
}

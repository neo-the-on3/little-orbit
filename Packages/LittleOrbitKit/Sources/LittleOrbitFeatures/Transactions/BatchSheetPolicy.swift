import Foundation

/// Whether a batch's progress sheet goes up just before its save (#285, D401, Tech Architect's review 5664921216).
///
/// The save runs on the main actor and blocks it, so the half-second timer can't fire while it runs: in Tester2's
/// Release N5 at 4c6a128 (comment 6439237570) the timer's deadline fell inside the save in all 18 batches, and the
/// sheet never showed. So once the rows are built, and the number of rows the save changes is known, this decides
/// before the save starts. The timer still covers the build, which runs off the main actor.
enum BatchSheetPolicy {
    /// What the progress does just before the save.
    enum Decision: Equatable, Sendable {
        /// The timer already showed the sheet: it stays, and the save starts after one turn.
        case keepShown
        /// The sheet goes up in "Saving…" with the bar full, and the save waits until it has drawn.
        case show
        /// No sheet: the run will end in well under half a second.
        case skip
    }

    /// Time already spent before the save at which the sheet shows. The save and the refresh after it still take
    /// at least as long again, so a run that got here by then ends past half a second.
    static let elapsedThatShowsSheet = Duration.milliseconds(250)

    /// Rows the save changes at which the sheet shows, however quick the build was.
    ///
    /// Calibrated from Tester2's Release N5 at 4c6a128 (comment 6439237570), one window: `write.save` took 349–613
    /// ms on the main thread for 2,501–3,334 changed rows, and whole runs took 1.28–1.65 s, or about 0.38–0.66 ms
    /// a row end to end. At the slower rate, 0.5 s is about 760 rows, so from 750 rows a run is expected to pass
    /// about half a second and shows the sheet.
    static let rowsThatShowSheet = 750

    /// The decision once the rows are built: `elapsed` since the batch started, `changedRows` the save will write,
    /// and whether the timer has already shown the sheet.
    static func beforeSave(elapsed: Duration, changedRows: Int, isShown: Bool) -> Decision {
        if isShown {
            return .keepShown
        }
        if elapsed >= elapsedThatShowsSheet || changedRows >= rowsThatShowSheet {
            return .show
        }
        return .skip
    }
}

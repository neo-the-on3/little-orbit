import Foundation

#if canImport(OSLog)
    import OSLog
#endif

/// The app's log for store problems that don't stop it (D293.3). Each event is a fixed message with the error's
/// domain and code only: never a path, a name or any other user data.
public enum StoreLog {
    public enum Event: String, Sendable {
        case defaultSeedFailed = "The default categories couldn't be seeded; the next launch tries again."
        case seedMarkerNotWritten = "The pending-seed marker couldn't be written; this store won't be seeded."
        case seedMarkerNotRemoved = "The pending-seed marker couldn't be removed; the empty-store check still applies."
        case scheduledCatchUpFailed =
            "Scheduled items couldn't be caught up; the next launch or activation tries again."
        case scheduledItemsNotRecorded = "Some scheduled items couldn't be recorded; they're tried again next time."
        case scheduledItemsCreatedAfterToday =
            "Some scheduled items were created on a later day than today; nothing is due for them until then."
        case watchSnapshotFailed = "The Apple Watch snapshot couldn't be made; the next change tries again."
        case watchPublishFailed = "The Apple Watch snapshot couldn't be sent; the next change tries again."
        case watchRequestUnreadable = "A request from Apple Watch couldn't be read; nothing was changed."
        case watchRequestNewer = "A request from a newer Apple Watch app couldn't be read; nothing was changed."
        case watchRequestsNotApplied =
            "Some Apple Watch requests couldn't be applied; they're tried again at the next activation."
        case watchRequestsRefused = "Some Apple Watch requests were refused; nothing was recorded for them."
    }

    #if canImport(OSLog)
        private static let logger = Logger(subsystem: "LittleOrbit", category: "Store")
    #endif

    /// An event with no error to report, such as some scheduled items left unrecorded.
    public static func notice(_ event: Event) {
        #if canImport(OSLog)
            logger.notice("\(event.rawValue, privacy: .public)")
        #endif
    }

    public static func failure(_ event: Event, _ error: any Error) {
        let error = error as NSError
        #if canImport(OSLog)
            logger.error(
                "\(event.rawValue, privacy: .public) (\(error.domain, privacy: .public) \(error.code, privacy: .public))"
            )
        #endif
    }
}

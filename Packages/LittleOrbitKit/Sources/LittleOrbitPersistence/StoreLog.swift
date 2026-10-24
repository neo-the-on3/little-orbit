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
    }

    #if canImport(OSLog)
        private static let logger = Logger(subsystem: "LittleOrbit", category: "Store")
    #endif

    public static func failure(_ event: Event, _ error: any Error) {
        let error = error as NSError
        #if canImport(OSLog)
            logger.error(
                "\(event.rawValue, privacy: .public) (\(error.domain, privacy: .public) \(error.code, privacy: .public))"
            )
        #endif
    }
}

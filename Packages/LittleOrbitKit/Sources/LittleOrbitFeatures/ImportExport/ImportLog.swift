import Foundation

#if canImport(OSLog)
    import OSLog
#endif

/// The log for CSV import and export (#30). Fixed messages and counts only: never a file name, a path, a row's
/// contents or any other user data.
enum ImportLog {
    enum Event: String, Sendable {
        case fileUnreadable = "The picked file couldn't be read."
        case fileRefused = "The picked file is empty or isn't CSV text."
        case ledgerUnreadable = "The ledger couldn't be read for an import."
        case commitFailed = "An import failed; nothing was saved."
        case undone = "An import was undone."
        case undoFailed = "Undo Import failed; nothing was removed."
        case undoEnded = "Undo Import ended: the data changed after the import."
        case exportFailed = "A CSV export couldn't be made."
    }

    #if canImport(OSLog)
        private static let logger = Logger(subsystem: "LittleOrbit", category: "CSV")
    #endif

    static func event(_ event: Event) {
        #if canImport(OSLog)
            logger.notice("\(event.rawValue, privacy: .public)")
        #endif
    }

    static func opened(rows: Int, columns: Int) {
        #if canImport(OSLog)
            logger.info("Opened a CSV file: \(rows, privacy: .public) rows, \(columns, privacy: .public) columns.")
        #endif
    }

    static func imported(_ count: Int) {
        #if canImport(OSLog)
            logger.info("Imported \(count, privacy: .public) transactions.")
        #endif
    }

    static func exported(_ count: Int) {
        #if canImport(OSLog)
            logger.info("Exported \(count, privacy: .public) transactions.")
        #endif
    }
}

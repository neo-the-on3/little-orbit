import Foundation

/// Why applying a watch request on the iPhone threw, sorted by whether trying again could ever work (D378).
///
/// - `permanent`: the ledger refused the change itself (a `LedgerValidationError`, such as a category it can't
///   record to any more). Trying again refuses it again, so the request is answered `refused` and isn't kept.
/// - `temporary`: anything else, such as the store failing to save or the disk being full. The request is kept and
///   tried again, and nothing is dropped.
///
/// An unknown error is temporary, so a request is never thrown away on a guess.
public enum WatchRequestFailure: Equatable, Sendable {
    case permanent
    case temporary

    public init(_ error: any Error) {
        self = error is LedgerValidationError ? .permanent : .temporary
    }
}

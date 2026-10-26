/// The WatchConnectivity dictionary keys both apps use (#197 item 10). Each value is `WatchMessageCodec` data, which
/// carries its own version.
enum WatchLinkKeys {
    /// The application context's snapshot.
    static let snapshot = "scheduled.snapshot"
    /// A queued user-info transfer's Pay or Skip request.
    static let request = "scheduled.request"
    /// The request's ID as a string, beside it, so the watch can tell which transfer finished (D377). The iPhone
    /// doesn't read it.
    static let requestID = "scheduled.requestID"
}

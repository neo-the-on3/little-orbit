import Foundation

/// The WatchConnectivity dictionaries both apps use (#197 item 10), built and read here so the fakes in the tests
/// carry exactly what the sessions do. Each payload is `WatchMessageCodec` data, which carries its own version.
public enum WatchLinkKeys {
    /// The application context's snapshot.
    public static let snapshot = "scheduled.snapshot"
    /// The application context's publish stamp, beside the snapshot and outside it. The watch doesn't read it
    /// (Tester F1, Tech Architect 5647974743).
    public static let stamp = "scheduled.stamp"
    /// A queued user-info transfer's Pay or Skip request.
    public static let request = "scheduled.request"
    /// The request's ID as a string, beside it, so the watch can tell which transfer finished (D377). The iPhone
    /// doesn't read it.
    public static let requestID = "scheduled.requestID"

    /// The application context for one publish.
    public static func applicationContext(_ context: WatchApplicationContext) -> [String: Any] {
        [snapshot: context.snapshot, stamp: NSNumber(value: context.stamp)]
    }

    /// The snapshot in an application context; any stamp beside it is ignored.
    public static func snapshot(in context: [String: Any]) -> Data? {
        context[snapshot] as? Data
    }

    /// The user info that queues one request.
    public static func userInfo(request data: Data, id: UUID) -> [String: Any] {
        [request: data, requestID: id.uuidString]
    }

    /// The request in a user-info transfer.
    public static func request(in userInfo: [String: Any]) -> Data? {
        userInfo[request] as? Data
    }

    /// The request's ID in a user-info transfer.
    public static func requestID(in userInfo: [String: Any]) -> UUID? {
        (userInfo[requestID] as? String).flatMap(UUID.init(uuidString:))
    }
}

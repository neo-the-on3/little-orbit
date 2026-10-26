import Foundation

/// One publish of the iPhone's application context: the versioned snapshot, and beside it a stamp that grows with
/// every publish. WatchConnectivity drops a context identical to the one it already has, so without the stamp a
/// deliberate re-send to a watch app installed or reinstalled later would never arrive (Tester F1, Tech Architect
/// 5647974743). The stamp is outside the snapshot, so the snapshot's version doesn't change.
public struct WatchApplicationContext: Equatable, Sendable {
    public var snapshot: Data
    public var stamp: Int64

    public init(snapshot: Data, stamp: Int64) {
        self.snapshot = snapshot
        self.stamp = stamp
    }

    /// Room kept in the 48 KB cap for the stamp and the dictionary around the snapshot.
    public static let overheadBytes = 128
    /// The most the snapshot itself may take, so the whole context stays within `WatchMessageCodec.maxSnapshotBytes`.
    public static let snapshotLimit = WatchMessageCodec.maxSnapshotBytes - overheadBytes
}

/// Hands out publish stamps: milliseconds since 1970, and always more than the last one, even if the clock goes
/// back. Starting from the clock means a relaunch doesn't repeat a stamp the session already stored.
public struct WatchPublishStamp: Sendable {
    public private(set) var last: Int64 = 0

    public init() {}

    public mutating func next(now: Date) -> Int64 {
        let clock = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        last = max(last + 1, clock)
        return last
    }
}

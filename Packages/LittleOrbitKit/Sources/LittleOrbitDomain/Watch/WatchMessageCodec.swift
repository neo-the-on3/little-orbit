import Foundation

/// Encodes and decodes what goes over WatchConnectivity (#48): the snapshot (application context) and the Pay and
/// Skip requests (queued user info). Both are compact JSON carrying their version, so each side checks it before it
/// reads the rest.
public enum WatchMessageCodec {
    /// Kept under WatchConnectivity's application-context limit, with room for the dictionary around it.
    public static let maxSnapshotBytes = 48_000
    /// The most outcomes a snapshot reports back; older ones have long been read by the watch.
    public static let maxOutcomes = 50

    public enum DecodeError: Error, Equatable {
        /// Not a message this build can read at all.
        case malformed
        /// Written by a newer build: the reader keeps what it has instead of guessing.
        case newerVersion(Int)
    }

    // MARK: Snapshot

    /// The snapshot as data no larger than `limit`. If it's too large, upcoming rows are left off the end first,
    /// then due ones, and `isTruncated` is set; outcomes are kept, newest last, up to `maxOutcomes`.
    public static func encode(_ snapshot: WatchSnapshot, limit: Int = maxSnapshotBytes) throws -> Data {
        var snapshot = snapshot
        snapshot.outcomes = Array(snapshot.outcomes.suffix(maxOutcomes))
        let encoder = makeEncoder()
        var data = try encoder.encode(snapshot)
        guard data.count > limit else {
            return data
        }
        snapshot.isTruncated = true
        // Halve, then step back up, so a large list costs a few encodes rather than one per row.
        var kept = snapshot.scheduled.count
        repeat {
            kept /= 2
            var trimmed = snapshot
            trimmed.scheduled = Array(snapshot.scheduled.prefix(kept))
            data = try encoder.encode(trimmed)
        } while data.count > limit && kept > 0
        var best = data
        var count = kept
        while count < snapshot.scheduled.count {
            var trimmed = snapshot
            trimmed.scheduled = Array(snapshot.scheduled.prefix(count + 1))
            let next = try encoder.encode(trimmed)
            guard next.count <= limit else {
                break
            }
            best = next
            count += 1
        }
        return best
    }

    public static func decodeSnapshot(_ data: Data) throws(DecodeError) -> WatchSnapshot {
        try decode(WatchSnapshot.self, from: data)
    }

    // MARK: Requests

    public static func encode(_ request: WatchScheduledRequest) throws -> Data {
        try makeEncoder().encode(request)
    }

    public static func decodeRequest(_ data: Data) throws(DecodeError) -> WatchScheduledRequest {
        try decode(WatchScheduledRequest.self, from: data)
    }

    // MARK: Private

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws(DecodeError) -> Value {
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(WatchMessageVersionProbe.self, from: data), probe.version >= 1 else {
            throw .malformed
        }
        guard probe.version <= WatchSnapshot.currentVersion else {
            throw .newerVersion(probe.version)
        }
        guard let value = try? decoder.decode(type, from: data) else {
            throw .malformed
        }
        return value
    }
}

/// The version every message carries, read before the rest.
private struct WatchMessageVersionProbe: Decodable {
    let version: Int

    private enum CodingKeys: String, CodingKey {
        case version = "v"
    }
}

import Foundation
import Testing

@testable import LittleOrbitDomain

/// The snapshot and request encoding (#197 item 10): round trips, the version check, and the size limit.
@Suite("Watch message codec")
struct WatchMessageCodecTests {
    static let itemID = UUID(uuidString: "3A000000-0000-4000-8000-000000000001")!

    static func occurrence(_ day: Int, _ status: WatchScheduledStatus = .upcoming, name: String = "StreamBox")
        -> WatchScheduledOccurrence
    {
        WatchScheduledOccurrence(
            itemID: itemID,
            day: CalendarDay(year: 2026, month: 10, day: day),
            status: status,
            type: .expense,
            amount: Decimal(string: "649.00")!,
            currencyCode: "INR",
            details: name,
            categoryName: "Entertainment",
            accountName: "Everyday Savings",
        )
    }

    static let snapshot =
        WatchSnapshot(
            today: CalendarDay(year: 2026, month: 10, day: 20),
            scheduled: [occurrence(15, .overdue), occurrence(20, .dueToday)],
            outcomes: [WatchRequestOutcome(requestID: UUID(), result: .alreadySkipped)],
        )

    @Test("A snapshot decodes to what was encoded, at the current version")
    func snapshotRoundTrip() throws {
        let data = try WatchMessageCodec.encode(Self.snapshot)
        let decoded = try WatchMessageCodec.decodeSnapshot(data)
        #expect(decoded == Self.snapshot)
        #expect(decoded.version == WatchSnapshot.currentVersion)
        #expect(!decoded.isTruncated)
    }

    @Test("A request decodes to what was encoded, keyed by its occurrence")
    func requestRoundTrip() throws {
        let request = WatchScheduledRequest(
            action: .pay,
            itemID: Self.itemID,
            occurrence: CalendarDay(year: 2026, month: 10, day: 20),
            tappedOn: CalendarDay(year: 2026, month: 10, day: 21),
        )
        let decoded = try WatchMessageCodec.decodeRequest(try WatchMessageCodec.encode(request))
        #expect(decoded == request)
        #expect(decoded.occurrenceKey == ScheduledKey.occurrenceID(item: Self.itemID, day: request.occurrence))
        #expect(
            decoded.settlement
                == .pay(itemID: Self.itemID, occurrence: request.occurrence, postedOn: request.tappedOn)
        )
    }

    @Test("A newer version is refused, not guessed at, for snapshots and requests")
    func newerVersion() throws {
        var newer = Self.snapshot
        newer.version = WatchSnapshot.currentVersion + 1
        let data = try JSONEncoder().encode(newer)
        #expect(throws: WatchMessageCodec.DecodeError.newerVersion(WatchSnapshot.currentVersion + 1)) {
            try WatchMessageCodec.decodeSnapshot(data)
        }
        var request = WatchScheduledRequest(
            action: .skip,
            itemID: Self.itemID,
            occurrence: CalendarDay(year: 2026, month: 10, day: 20),
            tappedOn: CalendarDay(year: 2026, month: 10, day: 20),
        )
        request.version = 7
        #expect(throws: WatchMessageCodec.DecodeError.newerVersion(7)) {
            try WatchMessageCodec.decodeRequest(try JSONEncoder().encode(request))
        }
    }

    @Test("Data with no version, version 0 or the wrong shape is malformed")
    func malformed() {
        for text in ["{}", "{\"v\":0,\"t\":{}}", "{\"v\":1}", "not json", "{\"v\":\"1\"}"] {
            #expect(throws: WatchMessageCodec.DecodeError.malformed) {
                try WatchMessageCodec.decodeSnapshot(Data(text.utf8))
            }
            #expect(throws: WatchMessageCodec.DecodeError.malformed) {
                try WatchMessageCodec.decodeRequest(Data(text.utf8))
            }
        }
    }

    @Test("Version 1 ignores fields it doesn’t know, so an added optional field needs no new version")
    func unknownFieldsIgnored() throws {
        let data = try WatchMessageCodec.encode(Self.snapshot)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["future"] = ["anything": 1]
        let decoded = try WatchMessageCodec.decodeSnapshot(try JSONSerialization.data(withJSONObject: object))
        #expect(decoded == Self.snapshot)
    }

    @Test("A snapshot too large for WatchConnectivity drops rows from the end, keeps order, and says so")
    func sizeLimit() throws {
        let long = String(repeating: "Long description ", count: 20)
        var snapshot = Self.snapshot
        snapshot.scheduled = (1...28)
            .map { Self.occurrence($0, $0 < 20 ? .overdue : .upcoming, name: "\($0) \(long)") }
        let full = try WatchMessageCodec.encode(snapshot, limit: .max)
        let limit = full.count / 2
        let data = try WatchMessageCodec.encode(snapshot, limit: limit)
        #expect(data.count <= limit)
        let decoded = try WatchMessageCodec.decodeSnapshot(data)
        #expect(decoded.isTruncated)
        #expect(!decoded.scheduled.isEmpty && decoded.scheduled.count < snapshot.scheduled.count)
        #expect(decoded.scheduled == Array(snapshot.scheduled.prefix(decoded.scheduled.count)))
        // As many rows as fit: one more would go over.
        var oneMore = decoded
        oneMore.scheduled = Array(snapshot.scheduled.prefix(decoded.scheduled.count + 1))
        #expect(try JSONEncoder().encode(oneMore).count > limit)
    }

    @Test("A snapshot reports at most the newest 50 outcomes")
    func outcomesCapped() throws {
        var snapshot = Self.snapshot
        snapshot.outcomes = (0..<80).map { _ in WatchRequestOutcome(requestID: UUID(), result: .applied) }
        let decoded = try WatchMessageCodec.decodeSnapshot(try WatchMessageCodec.encode(snapshot))
        #expect(decoded.outcomes == Array(snapshot.outcomes.suffix(WatchMessageCodec.maxOutcomes)))
    }

    @Test("A typical snapshot is small: 30 rows stay well under the limit")
    func typicalSize() throws {
        var snapshot = Self.snapshot
        snapshot.scheduled = (1...30).map { Self.occurrence($0 % 28 + 1) }
        let data = try WatchMessageCodec.encode(snapshot)
        #expect(data.count < WatchMessageCodec.maxSnapshotBytes / 4)
    }
}

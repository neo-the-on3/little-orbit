import Foundation
import LittleOrbitDomain

/// The watch requests the iPhone hasn't applied yet, and the outcomes it reports back, in this device's app
/// settings (#197 item 10). A request whose save failed is tried again at the next launch or activation. Only IDs,
/// days and results: never names or amounts. It isn't ledger data, so no backup holds it and the store's schema
/// doesn't change.
@MainActor
public final class UserDefaultsWatchRequestInbox: WatchRequestInboxStore {
    static let requestsKey = "watch.scheduled.keptRequests"
    static let outcomesKey = "watch.scheduled.outcomes"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func keptRequests() -> [WatchScheduledRequest] {
        read([WatchScheduledRequest].self, Self.requestsKey) ?? []
    }

    public func setKeptRequests(_ requests: [WatchScheduledRequest]) {
        write(requests, Self.requestsKey)
    }

    public func outcomes() -> [WatchRequestOutcome] {
        read([WatchRequestOutcome].self, Self.outcomesKey) ?? []
    }

    public func setOutcomes(_ outcomes: [WatchRequestOutcome]) {
        write(outcomes, Self.outcomesKey)
    }

    private func read<Value: Decodable>(_ type: Value.Type, _ key: String) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func write(_ values: [some Encodable], _ key: String) {
        guard !values.isEmpty, let data = try? JSONEncoder().encode(values) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

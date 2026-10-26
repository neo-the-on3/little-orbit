#if DEBUG
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitPersistence
    import Testing

    @testable import LittleOrbitFeatures

    /// `-LittleOrbitWatchNotices` seeds the real notice store so the real card shows (UI Designer 6407485986).
    @MainActor
    @Suite("Watch notices launch hook (Debug only)")
    struct WatchNoticesLaunchPresetTests {
        private let argument = WatchNoticesLaunchPreset.argument
        let scene: ScheduledScene

        init() throws {
            scene = try ScheduledScene()
        }

        @Test("Reads each value exactly, and nothing without one")
        func parsesArguments() {
            #expect(argument == "-LittleOrbitWatchNotices")
            for preset in WatchNoticesLaunchPreset.allCases {
                #expect(WatchNoticesLaunchPreset.preset(in: ["App", argument, preset.rawValue]) == preset)
            }
            #expect(
                WatchNoticesLaunchPreset.allCases.map(\.rawValue) == [
                    "refused-pay", "refused-skip", "mixed", "refused-group",
                ]
            )
            #expect(WatchNoticesLaunchPreset.preset(in: ["App"]) == nil)
            #expect(WatchNoticesLaunchPreset.preset(in: ["App", argument]) == nil)
            #expect(WatchNoticesLaunchPreset.preset(in: ["App", argument, "Refused-Pay"]) == nil)
            #expect(WatchNoticesLaunchPreset.preset(in: ["App", argument, "refused"]) == nil)
        }

        @Test("Each preset's notices: IDs only, against the items in order, repeating when there are too few")
        func noticeShapes() {
            let first = UUID()
            let second = UUID()
            let pay = WatchNoticesLaunchPreset.refusedPay.notices(itemIDs: [first, second])
            #expect(
                pay.map(\.reason) == [.refusedOnSave] && pay.map(\.action) == [.pay] && pay.map(\.itemID) == [first]
            )
            let skip = WatchNoticesLaunchPreset.refusedSkip.notices(itemIDs: [first])
            #expect(skip.map(\.reason) == [.refusedOnSave] && skip.map(\.action) == [.skip])
            let mixed = WatchNoticesLaunchPreset.mixed.notices(itemIDs: [first, second])
            #expect(mixed.map(\.reason) == [.itemChanged, .refusedOnSave])
            #expect(mixed.map(\.itemID) == [first, second])
            let group = WatchNoticesLaunchPreset.refusedGroup.notices(itemIDs: [first, second])
            #expect(group.count == 3 && group.allSatisfy { $0.reason == .refusedOnSave })
            #expect(group.map(\.itemID) == [first, second, first])
            #expect(Set(group.map(\.id)).count == 3)
            #expect(WatchNoticesLaunchPreset.mixed.notices(itemIDs: []).isEmpty)
        }

        /// Seeds through the settings-backed store the app uses, then reads the card the list would show.
        private func card(for value: String?) throws -> (WatchRequestNoticeCard?, [WatchRequestNotice]) {
            let name = "WatchNoticesLaunchPresetTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let inbox = UserDefaultsWatchRequestInbox(defaults: defaults)
            let arguments = ["App"] + (value.map { [argument, $0] } ?? [])
            WatchNoticesLaunchPreset.seed(arguments: arguments, repository: scene.repository, inbox: inbox)
            let useCases = DefaultWatchPhoneUseCases(
                repository: scene.repository,
                inbox: inbox,
                today: { CalendarDay(year: 2026, month: 10, day: 20) },
            )
            let notices = inbox.notices()
            return (WatchRequestNoticeViewModel(useCases: useCases).card, notices)
        }

        @Test("refused-pay and refused-skip give the real single cards for an existing item, with View Item")
        func singleCards() throws {
            let plan = scene.item("Phone Plan", day: 20, month: 10)
            try scene.add(plan)
            let pay = try #require(try card(for: "refused-pay").0)
            #expect(pay.title == WatchRequestNoticeText.payTitle)
            #expect(pay.message.contains("Phone Plan"))
            #expect(pay.itemID == plan.id)
            let skip = try #require(try card(for: "refused-skip").0)
            #expect(skip.title == WatchRequestNoticeText.skipTitle)
            #expect(skip.itemID == plan.id)
        }

        @Test("mixed and refused-group give one grouped card each, OK only, with D379's wording")
        func groupedCards() throws {
            try scene.add(scene.item("Phone Plan", day: 20, month: 10))
            try scene.add(scene.item("StreamBox", day: 21, month: 10))
            let mixed = try #require(try card(for: "mixed").0)
            #expect(mixed.title == WatchRequestNoticeText.severalChangedTitle)
            #expect(mixed.message.contains(WatchRequestNoticeText.severalMixed(2)))
            #expect(mixed.itemID == nil)
            let group = try #require(try card(for: "refused-group").0)
            #expect(group.message.contains(WatchRequestNoticeText.severalRefused(3)))
            #expect(group.itemID == nil)
        }

        @Test("No argument, an unknown value or no scheduled items seed nothing")
        func seedsNothing() throws {
            #expect(try card(for: "refused-pay").1.isEmpty)
            try scene.add(scene.item("Phone Plan", day: 20, month: 10))
            #expect(try card(for: nil).1.isEmpty)
            #expect(try card(for: "nonsense").1.isEmpty)
            #expect(try card(for: "mixed").1.count == 2)
        }
    }
#endif

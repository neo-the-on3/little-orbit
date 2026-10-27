#if DEBUG
    import Foundation
    import LittleOrbitDomain
    import Testing

    @testable import LittleOrbitFeatures

    /// The Debug-only delayed delete (#258 testing): the arguments, and a delete by name as another window's.
    @MainActor
    @Suite("Scheduled delete launch arguments (Debug)")
    struct ScheduledDeleteLaunchTests {
        private let name = ScheduledDeleteLaunch.nameArgument
        private let after = ScheduledDeleteLaunch.delayArgument

        @Test("The name is trimmed and needed; the delay is seconds above zero, capped at 10 minutes")
        func arguments() {
            #expect(ScheduledDeleteLaunch.name(in: ["app", name, " Phone Plan "]) == "Phone Plan")
            #expect(ScheduledDeleteLaunch.name(in: ["app", name, "  "]) == nil)
            #expect(ScheduledDeleteLaunch.name(in: ["app", name]) == nil)
            #expect(ScheduledDeleteLaunch.delay(in: ["app", after, "20"]) == .seconds(20))
            #expect(ScheduledDeleteLaunch.delay(in: ["app", after, "1.5"]) == .milliseconds(1_500))
            #expect(ScheduledDeleteLaunch.delay(in: ["app", after, "1e16"]) == .seconds(600))
            for bad in ["0", "-3", "nan", "inf", "", "soon"] {
                #expect(ScheduledDeleteLaunch.delay(in: ["app", after, bad]) == nil)
            }
            #expect(ScheduledDeleteLaunch.delay(in: ["app"]) == nil)
        }

        @Test("A delete by name goes through the delete use case and reloads every window; an unknown name doesn't")
        func deletesByName() throws {
            let scene = try ScheduledScene()
            let phone = scene.item("Phone Plan", day: 5)
            let electricity = scene.item("Electricity", day: 12)
            try scene.add(phone, electricity)
            let feature = scene.feature()
            let revision = feature.revision
            #expect(!feature.deleteItem(named: "Gym"))
            #expect(feature.revision == revision)
            #expect(feature.deleteItem(named: "Phone Plan"))
            #expect(feature.revision > revision)
            let listing = try scene.useCases.load.listing()
            #expect(listing.item(phone.id) == nil)
            #expect(listing.item(electricity.id) != nil)
        }
    }
#endif

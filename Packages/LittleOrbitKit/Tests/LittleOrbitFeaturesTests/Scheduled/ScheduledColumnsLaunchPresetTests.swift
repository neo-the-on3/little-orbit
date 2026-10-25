#if DEBUG
    import Foundation
    import LittleOrbitFeatures
    import Testing

    /// The Debug-only `-LittleOrbitScheduledColumns <value>` launch argument for the Mac Scheduled Table's saved
    /// columns (#205).
    @MainActor
    @Suite("Scheduled columns launch argument (#205)")
    struct ScheduledColumnsLaunchPresetTests {
        private let argument = ScheduledColumnsLaunchPreset.argument

        @Test("Each value names its preset")
        func values() {
            #expect(argument == "-LittleOrbitScheduledColumns")
            #expect(ScheduledColumnsLaunchPreset.preset(in: ["App", argument, "repeat-shown"]) == .repeatShown)
            #expect(ScheduledColumnsLaunchPreset.preset(in: ["App", argument, "garbage"]) == .garbage)
            #expect(
                ScheduledColumnsLaunchPreset.preset(in: ["App", "-NSQuitAlwaysKeepsWindows", "NO", argument, "reset"])
                    == .reset
            )
        }

        @Test("A missing, empty, unknown or differently cased value is no preset")
        func ignored() {
            #expect(ScheduledColumnsLaunchPreset.preset(in: []) == nil)
            #expect(
                ScheduledColumnsLaunchPreset.preset(in: ["App", "-LittleOrbitScheduledToday", "2026-10-20"]) == nil
            )
            #expect(ScheduledColumnsLaunchPreset.preset(in: ["App", argument]) == nil)
            #expect(ScheduledColumnsLaunchPreset.preset(in: ["App", argument, ""]) == nil)
            #expect(ScheduledColumnsLaunchPreset.preset(in: ["App", argument, "Repeat-Shown"]) == nil)
            #expect(ScheduledColumnsLaunchPreset.preset(in: ["App", argument, "repeat"]) == nil)
            #expect(ScheduledColumnsLaunchPreset.preset(in: ["App", argument, "-NSDocumentRevisionsDebugMode"]) == nil)
        }

        @Test("The garbage value decodes as nothing")
        func garbage() {
            let value = ScheduledColumnsLaunchPreset.garbageValue
            #expect(!value.isEmpty)
            #expect(String(data: value, encoding: .utf8) == nil)
            #expect((try? JSONSerialization.jsonObject(with: value, options: [.fragmentsAllowed])) == nil)
            #expect((try? PropertyListSerialization.propertyList(from: value, format: nil)) == nil)
        }

        @Test("The first window takes the preset once; Repeat is shown once, and only for repeat-shown")
        func takeOnce() {
            #expect(ScheduledColumnsLaunchPreset.take(arguments: ["App", argument, "repeat-shown"]) == .repeatShown)
            #expect(ScheduledColumnsLaunchPreset.take(arguments: ["App", argument, "garbage"]) == nil)
            #expect(ScheduledColumnsLaunchPreset.takeShowsRepeat())
            #expect(!ScheduledColumnsLaunchPreset.takeShowsRepeat())
        }
    }
#endif

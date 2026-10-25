#if DEBUG
    import Foundation

    /// A testing hook in Debug builds only: `-LittleOrbitScheduledColumns <value>` at launch sets the Mac Scheduled
    /// Table's saved column customization (the "scheduledTableColumns" scene storage) in the first window that
    /// shows the Table, before the Table reads it. It's for checks that would otherwise need the header's column
    /// menu, which an on-screen pass can't open. Release builds have none of it. Nothing is logged.
    ///
    /// - `repeat-shown`: starts from the default customization with Repeat visible.
    /// - `garbage`: stores bytes no customization decodes from, so the Table must fall back to its defaults.
    /// - `reset`: clears the saved customization.
    public enum ScheduledColumnsLaunchPreset: String, CaseIterable, Sendable {
        case repeatShown = "repeat-shown"
        case garbage
        case reset

        /// The launch argument's name.
        public static let argument = "-LittleOrbitScheduledColumns"

        /// What `garbage` stores: not a property list, JSON or any encoded customization.
        public static let garbageValue = Data([0xFF, 0x00, 0xFE, 0x7B, 0x6E, 0x6F, 0x74])

        /// The preset the arguments name, or nil when the argument is absent, has no value after it, or names
        /// none of the presets. Values are matched exactly.
        public static func preset(in arguments: [String]) -> Self? {
            guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.endIndex else {
                return nil
            }
            return Self(rawValue: arguments[index + 1])
        }

        @MainActor private static var isTaken = false
        @MainActor private static var showsRepeat = false

        /// This launch's preset, once: the first window to ask gets it, and later windows get nil.
        @MainActor
        public static func take(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
            guard !isTaken else {
                return nil
            }
            isTaken = true
            let preset = preset(in: arguments)
            showsRepeat = preset == .repeatShown
            return preset
        }

        /// Whether the Table that's about to read the storage should show Repeat, once: `repeat-shown` is applied
        /// through the Table's own customization, so its saved form is always one SwiftUI wrote.
        @MainActor
        public static func takeShowsRepeat() -> Bool {
            defer { showsRepeat = false }
            return showsRepeat
        }
    }
#endif

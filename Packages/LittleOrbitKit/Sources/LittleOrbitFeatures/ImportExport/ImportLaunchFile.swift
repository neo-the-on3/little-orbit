#if DEBUG
    import Foundation

    /// A testing hook in Debug builds only: `-LittleOrbitImportCSV <path>` at launch opens the import sheet with that
    /// file, as if it had been picked in the system open panel, so an on-screen pass can run without driving the
    /// panel. Release builds have none of it. The path is never logged.
    public enum ImportLaunchFile {
        /// The launch argument's name.
        public static let argument = "-LittleOrbitImportCSV"

        /// The file the arguments name, or nil when the argument is absent or has no value after it. A relative
        /// path is read from the current folder, and a leading `~` is the home folder.
        public static func url(in arguments: [String]) -> URL? {
            guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.endIndex else {
                return nil
            }
            let value = arguments[index + 1]
            guard !value.isEmpty, !value.hasPrefix("-") else {
                return nil
            }
            return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
        }

        @MainActor private static var isTaken = false

        /// This launch's file, once: the first window to ask opens it, and later windows get nil.
        @MainActor
        static func take(arguments: [String] = ProcessInfo.processInfo.arguments) -> URL? {
            guard !isTaken else {
                return nil
            }
            isTaken = true
            return url(in: arguments)
        }
    }
#endif

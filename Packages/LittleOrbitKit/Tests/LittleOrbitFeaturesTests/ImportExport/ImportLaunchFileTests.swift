#if DEBUG
    import Foundation
    import LittleOrbitFeatures
    import Testing

    /// The Debug-only `-LittleOrbitImportCSV <path>` launch argument that opens the import sheet with a file (#190).
    @Suite("CSV import launch argument (#190)")
    struct ImportLaunchFileTests {
        @Test("A path after the argument names the file")
        func present() {
            let url = ImportLaunchFile.url(in: ["App", "-LittleOrbitImportCSV", "/tmp/bank.csv"])
            #expect(url == URL(fileURLWithPath: "/tmp/bank.csv"))
        }

        @Test("Other arguments around it are ignored")
        func amongOthers() {
            let arguments = ["App", "-NSDocumentRevisionsDebugMode", "YES", "-LittleOrbitImportCSV", "/tmp/a b.csv"]
            #expect(ImportLaunchFile.url(in: arguments)?.lastPathComponent == "a b.csv")
        }

        @Test("A leading tilde is the home folder")
        func tilde() throws {
            let url = try #require(ImportLaunchFile.url(in: ["App", "-LittleOrbitImportCSV", "~/bank.csv"]))
            #expect(!url.path.contains("~"))
            #expect(url.lastPathComponent == "bank.csv")
        }

        @Test("No argument, no file")
        func absent() {
            #expect(ImportLaunchFile.url(in: []) == nil)
            #expect(ImportLaunchFile.url(in: ["App", "-NSDocumentRevisionsDebugMode", "YES"]) == nil)
        }

        @Test("The argument without a value, an empty value or another option names no file")
        func missingValue() {
            #expect(ImportLaunchFile.url(in: ["App", "-LittleOrbitImportCSV"]) == nil)
            #expect(ImportLaunchFile.url(in: ["App", "-LittleOrbitImportCSV", ""]) == nil)
            #expect(ImportLaunchFile.url(in: ["App", "-LittleOrbitImportCSV", "-NSQuitAlwaysKeepsWindows"]) == nil)
        }
    }
#endif

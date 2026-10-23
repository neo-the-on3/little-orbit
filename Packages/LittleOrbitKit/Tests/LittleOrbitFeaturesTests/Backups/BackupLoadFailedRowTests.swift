import Foundation
import Testing

/// Tester F1 on #99: on iOS the "Couldn’t Load Backups" state sits in a List row, and a Button with the default
/// style there makes the whole row its tap target, so a tap on the symbol or the margin read the list again. The tap
/// target can't be checked without a UI test, which this project doesn't have, so this checks the source: the iOS
/// list gives Try Again the borderless style, which keeps its look in a row, and macOS, where it isn't in a row, keeps
/// the default.
@Suite("Only Try Again is tappable in the Couldn’t Load Backups row (D211.5)")
struct BackupLoadFailedRowTests {
    private static func source(_ name: String) throws -> String {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/LittleOrbitFeatures/Backups/Views/\(name)")
        return try String(contentsOf: file, encoding: .utf8)
    }

    /// The text from the first `BackupLoadFailedView(` up to the `} else if` that follows it.
    private static func loadFailedBranch(in source: String) -> Substring? {
        guard let start = source.range(of: "BackupLoadFailedView(window: window)"),
            let end = source.range(of: "} else if", range: start.upperBound..<source.endIndex)
        else { return nil }
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("On iOS, Try Again has the borderless style, so a tap elsewhere in the row does nothing")
    func iOSRowTapsOnlyTryAgain() throws {
        let branch = try #require(Self.loadFailedBranch(in: Self.source("BackupsIOSViews.swift")))
        #expect(branch.contains(".buttonStyle(.borderless)"))
    }

    @Test("macOS, where the view isn't in a List row, and the shared view keep the default button style")
    func macOSKeepsDefaultStyle() throws {
        let branch = try #require(Self.loadFailedBranch(in: Self.source("BackupsSettingsTab.swift")))
        #expect(!branch.contains(".buttonStyle("))
        let flow = try Self.source("BackupFlow.swift")
        let view = try #require(flow.range(of: "struct BackupLoadFailedView"))
        #expect(!flow[view.lowerBound...].contains(".buttonStyle("))
    }
}

import Foundation
import Testing

/// S82 (R7, D182.1): no password UI or copy is left in the app, its packages or its string catalogs.
@Suite("No password copy", .timeLimit(.minutes(2)))
struct NoPasswordCopyTests {
    /// The repository root, from this file's path: Packages/LittleOrbitKit/Tests/LittleOrbitFeaturesTests/Backups.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let forbidden = [
        "Incorrect password",
        "If you forget this password",
        "Enter Password",
        "SecureField",
        "Password (Optional)",
    ]

    @Test("No source or string catalog under Apps or Packages/LittleOrbitKit/Sources has password copy")
    func noPasswordCopy() throws {
        var checked = 0
        for folder in ["Apps", "Packages/LittleOrbitKit/Sources"] {
            let base = Self.root.appendingPathComponent(folder)
            let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard ["swift", "xcstrings", "strings", "plist"].contains(url.pathExtension) else {
                    continue
                }
                let text = try String(contentsOf: url, encoding: .utf8)
                checked += 1
                for phrase in Self.forbidden {
                    #expect(!text.contains(phrase), "\(phrase) in \(url.lastPathComponent)")
                }
            }
        }
        #expect(checked > 10)
    }
}

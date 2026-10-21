import Foundation
import XCTest

/// The unedited `get_variable_defs` responses in Fixtures/figma-variables.json.
/// Every value in this file is a string, as the Figma MCP tool returns it.
struct FigmaFixture {
    let semanticLight: [String: String]
    let semanticDark: [String: String]
    let primitives: [String: String]
    let typography: [String: String]
    let spacing: [String: String]
    let radiusElevation: [String: String]

    static func load() throws -> FigmaFixture {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "figma-variables", withExtension: "json", subdirectory: "Fixtures")
        )
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let root = try XCTUnwrap(object as? [String: Any])
        func section(_ name: String) throws -> [String: String] {
            try XCTUnwrap(root[name] as? [String: String], "Missing fixture section \(name)")
        }
        return FigmaFixture(
            semanticLight: try section("semanticLight"),
            semanticDark: try section("semanticDark"),
            primitives: try section("primitives"),
            typography: try section("typography"),
            spacing: try section("spacing"),
            radiusElevation: try section("radiusElevation"),
        )
    }
}

extension Dictionary where Key == String, Value == String {
    /// Entries whose name starts with one of the prefixes, such as `space/`.
    func entries(withPrefixes prefixes: [String]) -> [String: String] {
        filter { entry in prefixes.contains { entry.key.hasPrefix($0) } }
    }

    /// Colour entries only (values that start with `#`).
    var colors: [String: String] {
        filter { $0.value.hasPrefix("#") }
    }
}

/// Reads `name: value` pairs out of Figma's `Font(...)` and `Effect(...)` descriptions.
/// Parentheses are stripped, so `offset: (0, 1)` reads as `0, 1`.
func figmaField(_ name: String, in description: String) -> String? {
    guard let range = description.range(of: "\(name): ") else { return nil }
    let rest = description[range.upperBound...]
    var value = ""
    var depth = 0
    for character in rest {
        if character == "(" {
            depth += 1
            continue
        }
        if character == ")" {
            if depth == 0 { break }
            depth -= 1
            continue
        }
        if character == ",", depth == 0 { break }
        value.append(character)
    }
    return value.trimmingCharacters(in: .whitespaces)
}

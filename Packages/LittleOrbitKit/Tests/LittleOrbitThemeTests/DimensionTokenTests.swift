import XCTest

@testable import LittleOrbitTheme

final class DimensionTokenTests: XCTestCase {
    func testSpacingAndLayoutMatchFigma() throws {
        let figma = try FigmaFixture.load().spacing.entries(withPrefixes: ["space/", "margin/", "target/"])
        let tokens = Spacing.all + Layout.all

        XCTAssertEqual(Set(tokens.map(\.figmaName)), Set(figma.keys))
        for token in tokens {
            XCTAssertEqual(token.value, Double(figma[token.figmaName] ?? ""), token.figmaName)
        }
    }

    func testSpacingFollowsTheFourPointScale() {
        for token in Spacing.all where token.figmaName != "space/0_5" {
            XCTAssertEqual(token.value.truncatingRemainder(dividingBy: 4), 0, token.figmaName)
        }
        XCTAssertEqual(Spacing.spaceHalf, 2)
        XCTAssertEqual(Spacing.all.map(\.value), Spacing.all.map(\.value).sorted())
    }

    func testRadiiMatchFigma() throws {
        let figma = try FigmaFixture.load().radiusElevation.entries(withPrefixes: ["radius/"])

        XCTAssertEqual(Set(Radius.all.map(\.figmaName)), Set(figma.keys))
        for token in Radius.all {
            XCTAssertEqual(token.value, Double(figma[token.figmaName] ?? ""), token.figmaName)
        }
        XCTAssertEqual(Radius.medium, 12)
        XCTAssertEqual(Radius.extraLarge, 22)
    }

    func testElevationMatchesFigmaEffectStyles() throws {
        let figma = try FigmaFixture.load().radiusElevation.entries(withPrefixes: ["Elevation/"])

        XCTAssertTrue(Elevation.flat.layers.isEmpty)
        let shadowed = Elevation.all.filter { !$0.layers.isEmpty }
        XCTAssertEqual(Set(shadowed.map(\.figmaName)), Set(figma.keys))

        for token in shadowed {
            let effects = try XCTUnwrap(figma[token.figmaName]).components(separatedBy: "; ")
            XCTAssertEqual(token.layers.count, effects.count, token.figmaName)
            for (layer, effect) in zip(token.layers, effects) {
                XCTAssertTrue(effect.contains("DROP_SHADOW"), token.figmaName)
                XCTAssertEqual(layer.color.hexString, figmaField("color", in: effect)?.lowercased(), token.figmaName)
                let offset = (figmaField("offset", in: effect) ?? "")
                    .split(separator: ",")
                    .map { Double($0.trimmingCharacters(in: .whitespaces)) }
                XCTAssertEqual(offset, [layer.offsetX, layer.offsetY], token.figmaName)
                XCTAssertEqual(layer.blur, Double(figmaField("radius", in: effect) ?? ""), token.figmaName)
                XCTAssertEqual(layer.spread, Double(figmaField("spread", in: effect) ?? ""), token.figmaName)
            }
        }
    }

    /// The SwiftUI modifier draws at most two layers and ignores spread.
    func testElevationFitsTheSwiftUIModifier() {
        for token in Elevation.all {
            XCTAssertLessThanOrEqual(token.layers.count, 2, token.figmaName)
            XCTAssertTrue(token.layers.allSatisfy { $0.spread == 0 }, token.figmaName)
        }
    }
}

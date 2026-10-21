import XCTest

@testable import LittleOrbitTheme

final class TypographyTests: XCTestCase {
    private var allStyles: [TypeStyle] {
        Typography.IOS.all + Typography.MacOS.all + Typography.WatchOS.all + Typography.Amount.all
    }

    func testEveryFigmaTextStyleMatches() throws {
        let figma = try FigmaFixture.load().typography.filter { $0.value.hasPrefix("Font(") }
        let styles = Dictionary(uniqueKeysWithValues: allStyles.map { ($0.figmaName, $0) })

        XCTAssertEqual(Set(styles.keys), Set(figma.keys))
        for (name, description) in figma {
            let style = try XCTUnwrap(styles[name], name)
            XCTAssertEqual(style.size, Double(figmaField("size", in: description) ?? ""), "\(name) size")
            XCTAssertEqual(style.weight.rawValue, Int(figmaField("weight", in: description) ?? ""), "\(name) weight")
            XCTAssertEqual(
                style.lineHeight,
                Double(figmaField("lineHeight", in: description) ?? ""),
                "\(name) line height",
            )
            let tracking = try XCTUnwrap(Double(figmaField("letterSpacing", in: description) ?? ""), name)
            XCTAssertEqual(style.letterSpacing, tracking, accuracy: 0.005, "\(name) letter spacing")
        }
    }

    func testGroupSizes() {
        XCTAssertEqual(Typography.IOS.all.count, 14)
        XCTAssertEqual(Typography.MacOS.all.count, 12)
        XCTAssertEqual(Typography.WatchOS.all.count, 9)
        XCTAssertEqual(Typography.Amount.all.count, 8)
        XCTAssertEqual(allStyles.count, Set(allStyles.map(\.figmaName)).count)
    }

    func testEachStyleMapsToTheAppleTextStyleItIsNamedAfter() {
        let expected: [String: TypeStyle.TextStyle] = [
            "Large Title": .largeTitle, "Title 1": .title1, "Title 2": .title2, "Title 3": .title3,
            "Headline": .headline, "Body": .body, "Callout": .callout, "Subheadline": .subheadline,
            "Footnote": .footnote, "Caption 1": .caption1, "Caption 2": .caption2,
        ]
        for style in Typography.IOS.all + Typography.MacOS.all + Typography.WatchOS.all {
            let name = String(style.figmaName.split(separator: "/")[1])
                .replacingOccurrences(of: " Emphasized", with: "")
            XCTAssertEqual(style.textStyle, expected[name], style.figmaName)
        }
    }

    func testAmountsUseRoundedMonospacedDigitsAndOtherStylesDoNot() {
        for style in Typography.Amount.all {
            XCTAssertEqual(style.design, .rounded, style.figmaName)
            XCTAssertTrue(style.monospacedDigits, style.figmaName)
        }
        for style in Typography.IOS.all + Typography.MacOS.all + Typography.WatchOS.all {
            XCTAssertEqual(style.design, .standard, style.figmaName)
            XCTAssertFalse(style.monospacedDigits, style.figmaName)
        }
    }

    func testSpotChecksAgainstFigma() {
        XCTAssertEqual(Typography.IOS.body.size, 17)
        XCTAssertEqual(Typography.IOS.body.lineHeight, 22)
        XCTAssertEqual(Typography.IOS.bodyEmphasized.weight, .semibold)
        XCTAssertEqual(Typography.MacOS.headline.weight, .bold)
        XCTAssertEqual(Typography.MacOS.headline.size, 13)
        XCTAssertEqual(Typography.WatchOS.largeTitle.size, 36)
        XCTAssertEqual(Typography.Amount.iOSHero.size, 34)
        XCTAssertEqual(Typography.Amount.iOSHero.textStyle, .largeTitle)
        XCTAssertEqual(Typography.Amount.macOSBody.weight, .medium)
    }
}

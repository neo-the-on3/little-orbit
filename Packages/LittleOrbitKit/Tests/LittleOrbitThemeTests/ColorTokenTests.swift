import XCTest

@testable import LittleOrbitTheme

final class ColorTokenTests: XCTestCase {
    func testEverySemanticColorMatchesFigmaInLightAndDarkMode() throws {
        let figma = try FigmaFixture.load()
        let light = figma.semanticLight.colors
        let dark = figma.semanticDark.colors

        XCTAssertEqual(Set(light.keys), Set(dark.keys), "Figma Light and Dark frames list different variables")
        XCTAssertEqual(Set(ThemeColor.all.map(\.figmaName)), Set(light.keys))
        XCTAssertEqual(ThemeColor.all.count, 39)

        for token in ThemeColor.all {
            XCTAssertEqual(token.light.hexString, light[token.figmaName]?.lowercased(), "\(token.figmaName) light")
            XCTAssertEqual(token.dark.hexString, dark[token.figmaName]?.lowercased(), "\(token.figmaName) dark")
        }
    }

    func testCategoryHuesMatchFigmaPrimitives() throws {
        let figma = try FigmaFixture.load()
        let hues = figma.primitives.entries(withPrefixes: ["category/"])

        XCTAssertEqual(Set(CategoryColor.all.map(\.figmaName)), Set(hues.keys))
        XCTAssertEqual(CategoryColor.all.count, 13)
        for token in CategoryColor.all {
            XCTAssertEqual(token.light, token.dark, "\(token.figmaName) has one value in both modes")
            XCTAssertEqual(token.light.hexString, hues[token.figmaName]?.lowercased(), token.figmaName)
        }
    }

    func testSpotChecksAgainstFigma() {
        XCTAssertEqual(ThemeColor.bgPrimary.light.hexString, "#ffffff")
        XCTAssertEqual(ThemeColor.bgPrimary.dark.hexString, "#000000")
        XCTAssertEqual(ThemeColor.labelPrimary.light.hexString, "#0e0f13")
        XCTAssertEqual(ThemeColor.accentDefault.light.hexString, "#3a4fc2")  // brand/600
        XCTAssertEqual(ThemeColor.accentDefault.dark.hexString, "#97aaf5")  // brand/300
        XCTAssertEqual(ThemeColor.moneyPositive.dark.hexString, "#5fd594")
        XCTAssertEqual(ThemeColor.destructiveFill.light, ThemeColor.destructiveFill.dark)
        XCTAssertEqual(CategoryColor.teal.light.hexString, "#0f8577")
    }

    func testTokenNamesAreUnique() {
        let names = (ThemeColor.all + CategoryColor.all).map(\.figmaName)
        XCTAssertEqual(names.count, Set(names).count)
    }

    func testEveryColorIsOpaque() {
        for token in ThemeColor.all + CategoryColor.all {
            XCTAssertEqual(token.light.alpha, 255, token.figmaName)
            XCTAssertEqual(token.dark.alpha, 255, token.figmaName)
        }
    }

    /// Figma: every text/label token passes WCAG 4.5:1 on every background token it is used
    /// on (bg/primary, secondary, tertiary, grouped, grouped-secondary, elevated, fill/primary).
    /// label/disabled is exempt, as WCAG exempts disabled controls.
    func testTextColorsMeetWCAGContrastOnBackgroundsInBothModes() {
        let backgrounds = [
            ThemeColor.bgPrimary, ThemeColor.bgSecondary, ThemeColor.bgTertiary, ThemeColor.bgGrouped,
            ThemeColor.bgGroupedSecondary, ThemeColor.bgElevated, ThemeColor.fillPrimary,
        ]
        let foregrounds = [
            ThemeColor.labelPrimary, ThemeColor.labelSecondary, ThemeColor.labelTertiary,
            ThemeColor.moneyPositive, ThemeColor.moneyNegative, ThemeColor.moneyTransfer, ThemeColor.moneyNeutral,
            ThemeColor.statusOverspent, ThemeColor.statusWarning, ThemeColor.statusSuccess,
            ThemeColor.destructiveDefault,
        ]
        for foreground in foregrounds {
            for background in backgrounds {
                let light = foreground.light.contrastRatio(with: background.light)
                let dark = foreground.dark.contrastRatio(with: background.dark)
                XCTAssertGreaterThanOrEqual(light, 4.5, "\(foreground.figmaName) on \(background.figmaName), light")
                XCTAssertGreaterThanOrEqual(dark, 4.5, "\(foreground.figmaName) on \(background.figmaName), dark")
            }
        }
    }

    func testLabelOnAccentMeetsContrastOnAccent() {
        let token = ThemeColor.labelOnAccent
        XCTAssertGreaterThanOrEqual(token.light.contrastRatio(with: ThemeColor.accentDefault.light), 4.5)
        XCTAssertGreaterThanOrEqual(token.dark.contrastRatio(with: ThemeColor.accentDefault.dark), 4.5)
    }

    /// Figma: category hues are all at least 4.5:1 with a white glyph.
    func testCategoryHuesMeetContrastWithWhite() {
        let white = RGBAColor(red: 255, green: 255, blue: 255)
        for token in CategoryColor.all {
            XCTAssertGreaterThanOrEqual(token.light.contrastRatio(with: white), 4.5, token.figmaName)
        }
    }

    func testHexParsing() {
        XCTAssertEqual(RGBAColor(hex: "#3A4FC2"), RGBAColor(red: 0x3A, green: 0x4F, blue: 0xC2))
        XCTAssertEqual(RGBAColor(hex: "#0D0F1A0F")?.alpha, 15)
        XCTAssertEqual(RGBAColor(hex: "#0D0F1A0F")?.hexString, "#0d0f1a0f")
        XCTAssertNil(RGBAColor(hex: "3A4FC2"))
        XCTAssertNil(RGBAColor(hex: "#3A4FC"))
        XCTAssertNil(RGBAColor(hex: "#GGGGGG"))
    }
}

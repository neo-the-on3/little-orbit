/// One text style from the design system.
///
/// In SwiftUI, `Font.theme(_:)` maps a style to the system text style, design and weight, so
/// Dynamic Type scales it. `size`, `lineHeight` and `letterSpacing` record the Figma values
/// at the default Dynamic Type size; they are for traceability and tests, not for fixed sizes.
public struct TypeStyle: Hashable, Sendable {
    /// Apple's built-in text styles.
    public enum TextStyle: String, CaseIterable, Hashable, Sendable {
        case largeTitle
        case title1
        case title2
        case title3
        case headline
        case body
        case callout
        case subheadline
        case footnote
        case caption1
        case caption2
    }

    /// Font weights used in Figma, by their numeric weight.
    public enum Weight: Int, CaseIterable, Hashable, Sendable {
        case regular = 400
        case medium = 500
        case semibold = 600
        case bold = 700
    }

    /// System font designs used by the design system.
    public enum Design: Hashable, Sendable {
        case standard
        case rounded
    }

    /// The Figma text style name, such as `iOS/Body`.
    public let figmaName: String
    public let textStyle: TextStyle
    public let weight: Weight
    public let size: Double
    public let lineHeight: Double
    public let letterSpacing: Double
    public let design: Design
    public let monospacedDigits: Bool

    public init(
        _ figmaName: String,
        textStyle: TextStyle,
        weight: Weight,
        size: Double,
        lineHeight: Double,
        letterSpacing: Double,
        design: Design = .standard,
        monospacedDigits: Bool = false,
    ) {
        self.figmaName = figmaName
        self.textStyle = textStyle
        self.weight = weight
        self.size = size
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.design = design
        self.monospacedDigits = monospacedDigits
    }
}

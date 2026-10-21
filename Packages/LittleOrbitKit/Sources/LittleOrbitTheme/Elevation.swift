// Elevation effect styles from the Figma design system (page
// "Foundations / Radius & Elevation", node 7:255). Shadows are for floating surfaces only.
// In dark mode bg/elevated replaces shadows, so `themeElevation(_:)` draws none there.

/// One drop shadow layer, as Figma describes it. `blur` is Figma's blur radius in points.
public struct ShadowLayer: Hashable, Sendable {
    public let color: RGBAColor
    public let offsetX: Double
    public let offsetY: Double
    public let blur: Double
    public let spread: Double

    public init(color: RGBAColor, offsetX: Double, offsetY: Double, blur: Double, spread: Double = 0) {
        self.color = color
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.blur = blur
        self.spread = spread
    }
}

/// An elevation level: zero or more shadow layers.
public struct ElevationToken: Hashable, Sendable {
    /// The Figma effect style name, such as `Elevation/1 Card`.
    public let figmaName: String
    public let layers: [ShadowLayer]

    public init(_ figmaName: String, layers: [ShadowLayer]) {
        self.figmaName = figmaName
        self.layers = layers
    }
}

/// Elevation levels.
public enum Elevation {
    /// Figma `Elevation/0 Flat`: no shadow.
    public static let flat = ElevationToken("Elevation/0 Flat", layers: [])

    /// Figma `Elevation/1 Card`.
    public static let card = ElevationToken(
        "Elevation/1 Card",
        layers: [
            ShadowLayer(color: "#0D0F1A0F", offsetX: 0, offsetY: 1, blur: 3),
            ShadowLayer(color: "#0D0F1A0F", offsetX: 0, offsetY: 2, blur: 8),
        ],
    )

    /// Figma `Elevation/2 Sheet`.
    public static let sheet = ElevationToken(
        "Elevation/2 Sheet",
        layers: [
            ShadowLayer(color: "#0D0F1A1A", offsetX: 0, offsetY: -2, blur: 16)
        ],
    )

    /// Figma `Elevation/3 Popover`.
    public static let popover = ElevationToken(
        "Elevation/3 Popover",
        layers: [
            ShadowLayer(color: "#0D0F1A29", offsetX: 0, offsetY: 8, blur: 24),
            ShadowLayer(color: "#0D0F1A14", offsetX: 0, offsetY: 1, blur: 3),
        ],
    )

    /// Every elevation level, lowest first.
    public static let all: [ElevationToken] = [flat, card, sheet, popover]
}

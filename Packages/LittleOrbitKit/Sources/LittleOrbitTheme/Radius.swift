// Corner radius tokens from the Figma design system (collection
// "Radius", page "Foundations / Radius & Elevation", node 7:226). Values are points. Use them
// with continuous corners: RoundedRectangle(cornerRadius:style: .continuous).

/// Corner radii.
public enum Radius {
    /// Figma `radius/none`.
    public static let none: Double = 0
    /// Figma `radius/xs`.
    public static let extraSmall: Double = 4
    /// Figma `radius/sm`.
    public static let small: Double = 8
    /// Figma `radius/md`.
    public static let medium: Double = 12
    /// Figma `radius/lg`.
    public static let large: Double = 16
    /// Figma `radius/xl`.
    public static let extraLarge: Double = 22
    /// Figma `radius/full` (999). Figma labels it "capsule"; in SwiftUI prefer `Capsule()`.
    public static let full: Double = 999

    /// Every radius with its Figma variable name, smallest first.
    public static let all: [DimensionToken] = [
        DimensionToken("radius/none", value: none),
        DimensionToken("radius/xs", value: extraSmall),
        DimensionToken("radius/sm", value: small),
        DimensionToken("radius/md", value: medium),
        DimensionToken("radius/lg", value: large),
        DimensionToken("radius/xl", value: extraLarge),
        DimensionToken("radius/full", value: full),
    ]
}

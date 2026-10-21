// Spacing and layout tokens from the Figma design system (collection "Spacing",
// page "Foundations / Spacing & Layout", node 7:146). Values are points.

/// A named point value from Figma, such as `space/4` = 16.
public struct DimensionToken: Hashable, Sendable {
    /// The Figma variable name.
    public let figmaName: String
    public let value: Double

    public init(_ figmaName: String, value: Double) {
        self.figmaName = figmaName
        self.value = value
    }
}

/// The 4-pt spacing scale for padding and gaps.
public enum Spacing {
    /// Figma `space/0`.
    public static let space0: Double = 0
    /// Figma `space/0_5`.
    public static let spaceHalf: Double = 2
    /// Figma `space/1`.
    public static let space1: Double = 4
    /// Figma `space/2`.
    public static let space2: Double = 8
    /// Figma `space/3`.
    public static let space3: Double = 12
    /// Figma `space/4`.
    public static let space4: Double = 16
    /// Figma `space/5`.
    public static let space5: Double = 20
    /// Figma `space/6`.
    public static let space6: Double = 24
    /// Figma `space/8`.
    public static let space8: Double = 32
    /// Figma `space/10`.
    public static let space10: Double = 40
    /// Figma `space/12`.
    public static let space12: Double = 48
    /// Figma `space/16`.
    public static let space16: Double = 64

    /// Every spacing step with its Figma variable name, smallest first.
    public static let all: [DimensionToken] = [
        DimensionToken("space/0", value: space0),
        DimensionToken("space/0_5", value: spaceHalf),
        DimensionToken("space/1", value: space1),
        DimensionToken("space/2", value: space2),
        DimensionToken("space/3", value: space3),
        DimensionToken("space/4", value: space4),
        DimensionToken("space/5", value: space5),
        DimensionToken("space/6", value: space6),
        DimensionToken("space/8", value: space8),
        DimensionToken("space/10", value: space10),
        DimensionToken("space/12", value: space12),
        DimensionToken("space/16", value: space16),
    ]
}

/// Layout margins and minimum hit targets per platform, following the Apple HIG.
public enum Layout {
    /// Figma `margin/ios`.
    public static let marginIOS: Double = 16
    /// Figma `margin/ios-wide`.
    public static let marginIOSWide: Double = 20
    /// Figma `margin/macos`.
    public static let marginMacOS: Double = 20
    /// Figma `margin/watchos`.
    public static let marginWatchOS: Double = 8
    /// Figma `target/ios-min`.
    public static let minimumTargetIOS: Double = 44
    /// Figma `target/macos-min`.
    public static let minimumTargetMacOS: Double = 28
    /// Figma `target/watchos-min`.
    public static let minimumTargetWatchOS: Double = 38

    /// Every layout value with its Figma variable name.
    public static let all: [DimensionToken] = [
        DimensionToken("margin/ios", value: marginIOS),
        DimensionToken("margin/ios-wide", value: marginIOSWide),
        DimensionToken("margin/macos", value: marginMacOS),
        DimensionToken("margin/watchos", value: marginWatchOS),
        DimensionToken("target/ios-min", value: minimumTargetIOS),
        DimensionToken("target/macos-min", value: minimumTargetMacOS),
        DimensionToken("target/watchos-min", value: minimumTargetWatchOS),
    ]
}

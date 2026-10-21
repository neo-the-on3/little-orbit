/// Design tokens for little-orbit, taken from the Figma design system.
///
/// The token value types (``ColorToken``, ``TypeStyle``, ``ElevationToken``) and the
/// constants in ``ThemeColor``, ``CategoryColor``, ``Typography``, ``Spacing``, ``Layout``,
/// ``Radius`` and ``Elevation`` are plain Swift, so they build and are tested on Linux.
/// SwiftUI adapters (`Color(_:)`, `Font.theme(_:)`, `themeElevation(_:)`, ``ThemeSwatchView``)
/// compile only where SwiftUI exists.
public enum LittleOrbitTheme {
    public static let moduleName = "LittleOrbitTheme"

    /// Name of the Figma design system file the tokens come from. The file is private, so it is named, not linked.
    public static let designSystemFileName = "little-orbit-design-system"
}

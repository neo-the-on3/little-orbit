// Semantic colour tokens from the Figma design system (collection "Semantic",
// modes Light and Dark). Values were read with get_variable_defs on
// the "Semantic / Light" (6:9) and "Semantic / Dark" (6:222) frames. See docs/design-tokens.md
// before changing a value here.

/// Semantic colours. Use these in components and screens, never the primitives.
public enum ThemeColor {
    // MARK: Backgrounds

    /// Figma `bg/primary`.
    public static let bgPrimary = ColorToken("bg/primary", light: "#ffffff", dark: "#000000")
    /// Figma `bg/secondary`.
    public static let bgSecondary = ColorToken("bg/secondary", light: "#f2f3f7", dark: "#16181e")
    /// Figma `bg/tertiary`.
    public static let bgTertiary = ColorToken("bg/tertiary", light: "#ffffff", dark: "#1f222a")
    /// Figma `bg/grouped`.
    public static let bgGrouped = ColorToken("bg/grouped", light: "#f2f3f7", dark: "#000000")
    /// Figma `bg/grouped-secondary`.
    public static let bgGroupedSecondary = ColorToken("bg/grouped-secondary", light: "#ffffff", dark: "#16181e")
    /// Figma `bg/elevated`.
    public static let bgElevated = ColorToken("bg/elevated", light: "#ffffff", dark: "#1f222a")

    // MARK: Labels

    /// Figma `label/primary`.
    public static let labelPrimary = ColorToken("label/primary", light: "#0e0f13", dark: "#ffffff")
    /// Figma `label/secondary`.
    public static let labelSecondary = ColorToken("label/secondary", light: "#525868", dark: "#b4bac7")
    /// Figma `label/tertiary`.
    public static let labelTertiary = ColorToken("label/tertiary", light: "#5f6676", dark: "#8e95a5")
    /// Figma `label/on-accent`.
    public static let labelOnAccent = ColorToken("label/on-accent", light: "#ffffff", dark: "#131a3e")
    /// Figma `label/on-color`.
    public static let labelOnColor = ColorToken("label/on-color", light: "#ffffff", dark: "#ffffff")
    /// Figma `label/disabled`.
    public static let labelDisabled = ColorToken("label/disabled", light: "#8e95a5", dark: "#5f6676")

    // MARK: Separators

    /// Figma `separator/default`.
    public static let separatorDefault = ColorToken("separator/default", light: "#d1d5de", dark: "#3d4250")
    /// Figma `separator/strong`.
    public static let separatorStrong = ColorToken("separator/strong", light: "#b4bac7", dark: "#525868")

    // MARK: Fills

    /// Figma `fill/primary`.
    public static let fillPrimary = ColorToken("fill/primary", light: "#e6e8ee", dark: "#2a2e38")
    /// Figma `fill/secondary`.
    public static let fillSecondary = ColorToken("fill/secondary", light: "#f2f3f7", dark: "#1f222a")
    /// Figma `fill/disabled`.
    public static let fillDisabled = ColorToken("fill/disabled", light: "#e6e8ee", dark: "#2a2e38")

    // MARK: Accent

    /// Figma `accent/default`.
    public static let accentDefault = ColorToken("accent/default", light: "#3a4fc2", dark: "#97aaf5")
    /// Figma `accent/pressed`.
    public static let accentPressed = ColorToken("accent/pressed", light: "#2e3e9e", dark: "#bdcafa")
    /// Figma `accent/tint`.
    public static let accentTint = ColorToken("accent/tint", light: "#eef2ff", dark: "#1d265b")
    /// Figma `accent/on-tint`.
    public static let accentOnTint = ColorToken("accent/on-tint", light: "#2e3e9e", dark: "#bdcafa")

    // MARK: Money

    /// Figma `money/positive`.
    public static let moneyPositive = ColorToken("money/positive", light: "#0e6b3c", dark: "#5fd594")
    /// Figma `money/negative`.
    public static let moneyNegative = ColorToken("money/negative", light: "#bb2a30", dark: "#ff8f91")
    /// Figma `money/transfer`.
    public static let moneyTransfer = ColorToken("money/transfer", light: "#6431c9", dark: "#c5a8fa")
    /// Figma `money/neutral`.
    public static let moneyNeutral = ColorToken("money/neutral", light: "#0e0f13", dark: "#ffffff")

    // MARK: Status

    /// Figma `status/overspent`.
    public static let statusOverspent = ColorToken("status/overspent", light: "#a8232a", dark: "#ff8f91")
    /// Figma `status/overspent-bg`.
    public static let statusOverspentBg = ColorToken("status/overspent-bg", light: "#fdecec", dark: "#4a1416")
    /// Figma `status/warning`.
    public static let statusWarning = ColorToken("status/warning", light: "#9a5200", dark: "#f7be5a")
    /// Figma `status/warning-bg`.
    public static let statusWarningBg = ColorToken("status/warning-bg", light: "#fff4e2", dark: "#43280a")
    /// Figma `status/success`.
    public static let statusSuccess = ColorToken("status/success", light: "#0e6b3c", dark: "#5fd594")
    /// Figma `status/success-bg`.
    public static let statusSuccessBg = ColorToken("status/success-bg", light: "#e9f8ef", dark: "#0c3320")
    /// Figma `status/info`.
    public static let statusInfo = ColorToken("status/info", light: "#2e3e9e", dark: "#bdcafa")
    /// Figma `status/info-bg`.
    public static let statusInfoBg = ColorToken("status/info-bg", light: "#eef2ff", dark: "#1d265b")
    /// Figma `status/neutral`.
    public static let statusNeutral = ColorToken("status/neutral", light: "#525868", dark: "#b4bac7")
    /// Figma `status/neutral-bg`.
    public static let statusNeutralBg = ColorToken("status/neutral-bg", light: "#e6e8ee", dark: "#2a2e38")

    // MARK: Destructive

    /// Figma `destructive/default`.
    public static let destructiveDefault = ColorToken("destructive/default", light: "#bb2a30", dark: "#ff8f91")
    /// Figma `destructive/fill`.
    public static let destructiveFill = ColorToken("destructive/fill", light: "#bb2a30", dark: "#bb2a30")
    /// Figma `destructive/tint`.
    public static let destructiveTint = ColorToken("destructive/tint", light: "#fdecec", dark: "#4a1416")
    /// Figma `destructive/on-tint`.
    public static let destructiveOnTint = ColorToken("destructive/on-tint", light: "#a8232a", dark: "#ff8f91")

    /// Every semantic colour, in Figma order.
    public static let all: [ColorToken] = [
        bgPrimary,
        bgSecondary,
        bgTertiary,
        bgGrouped,
        bgGroupedSecondary,
        bgElevated,
        labelPrimary,
        labelSecondary,
        labelTertiary,
        labelOnAccent,
        labelOnColor,
        labelDisabled,
        separatorDefault,
        separatorStrong,
        fillPrimary,
        fillSecondary,
        fillDisabled,
        accentDefault,
        accentPressed,
        accentTint,
        accentOnTint,
        moneyPositive,
        moneyNegative,
        moneyTransfer,
        moneyNeutral,
        statusOverspent,
        statusOverspentBg,
        statusWarning,
        statusWarningBg,
        statusSuccess,
        statusSuccessBg,
        statusInfo,
        statusInfoBg,
        statusNeutral,
        statusNeutralBg,
        destructiveDefault,
        destructiveFill,
        destructiveTint,
        destructiveOnTint,
    ]
}

/// Category hues (Figma primitives `category/*`, published for category chips).
/// They have one value in both modes and always carry a white glyph.
public enum CategoryColor {
    /// Figma `category/red`.
    public static let red = ColorToken("category/red", light: "#d93b3b", dark: "#d93b3b")
    /// Figma `category/orange`.
    public static let orange = ColorToken("category/orange", light: "#c0521a", dark: "#c0521a")
    /// Figma `category/amber`.
    public static let amber = ColorToken("category/amber", light: "#9c6300", dark: "#9c6300")
    /// Figma `category/yellow`.
    public static let yellow = ColorToken("category/yellow", light: "#866c00", dark: "#866c00")
    /// Figma `category/lime`.
    public static let lime = ColorToken("category/lime", light: "#4f7710", dark: "#4f7710")
    /// Figma `category/green`.
    public static let green = ColorToken("category/green", light: "#1f7f45", dark: "#1f7f45")
    /// Figma `category/teal`.
    public static let teal = ColorToken("category/teal", light: "#0f8577", dark: "#0f8577")
    /// Figma `category/cyan`.
    public static let cyan = ColorToken("category/cyan", light: "#0b7fa3", dark: "#0b7fa3")
    /// Figma `category/blue`.
    public static let blue = ColorToken("category/blue", light: "#2f6fd6", dark: "#2f6fd6")
    /// Figma `category/indigo`.
    public static let indigo = ColorToken("category/indigo", light: "#4e55cf", dark: "#4e55cf")
    /// Figma `category/purple`.
    public static let purple = ColorToken("category/purple", light: "#8048d0", dark: "#8048d0")
    /// Figma `category/pink`.
    public static let pink = ColorToken("category/pink", light: "#c23f87", dark: "#c23f87")
    /// Figma `category/gray`.
    public static let gray = ColorToken("category/gray", light: "#5f6676", dark: "#5f6676")

    /// Every category hue, in Figma order.
    public static let all: [ColorToken] = [
        red,
        orange,
        amber,
        yellow,
        lime,
        green,
        teal,
        cyan,
        blue,
        indigo,
        purple,
        pink,
        gray,
    ]
}

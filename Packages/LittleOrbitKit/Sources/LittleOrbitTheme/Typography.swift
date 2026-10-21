// Text styles from the Figma design system (page
// "Foundations / Typography", node 7:5). Figma renders every style in Inter because SF
// is not available there; the sizes, weights, line heights and tracking are the SF values
// of the matching Apple text style at the default Dynamic Type size. Letter spacing is
// rounded to 0.01 pt. See docs/design-tokens.md before changing a value here.

/// Text style tokens, one namespace per platform plus money amounts.
public enum Typography {}

extension Typography {
    /// iOS and iPadOS (SF Pro), default Dynamic Type size.
    public enum IOS {
        /// Figma `iOS/Large Title`.
        public static let largeTitle = TypeStyle(
            "iOS/Large Title",
            textStyle: .largeTitle,
            weight: .regular,
            size: 34,
            lineHeight: 41,
            letterSpacing: 0.4,
        )
        /// Figma `iOS/Title 1`.
        public static let title1 = TypeStyle(
            "iOS/Title 1",
            textStyle: .title1,
            weight: .regular,
            size: 28,
            lineHeight: 34,
            letterSpacing: 0.38,
        )
        /// Figma `iOS/Title 2`.
        public static let title2 = TypeStyle(
            "iOS/Title 2",
            textStyle: .title2,
            weight: .regular,
            size: 22,
            lineHeight: 28,
            letterSpacing: -0.26,
        )
        /// Figma `iOS/Title 3`.
        public static let title3 = TypeStyle(
            "iOS/Title 3",
            textStyle: .title3,
            weight: .regular,
            size: 20,
            lineHeight: 25,
            letterSpacing: -0.45,
        )
        /// Figma `iOS/Headline`.
        public static let headline = TypeStyle(
            "iOS/Headline",
            textStyle: .headline,
            weight: .semibold,
            size: 17,
            lineHeight: 22,
            letterSpacing: -0.43,
        )
        /// Figma `iOS/Body`.
        public static let body = TypeStyle(
            "iOS/Body",
            textStyle: .body,
            weight: .regular,
            size: 17,
            lineHeight: 22,
            letterSpacing: -0.43,
        )
        /// Figma `iOS/Callout`.
        public static let callout = TypeStyle(
            "iOS/Callout",
            textStyle: .callout,
            weight: .regular,
            size: 16,
            lineHeight: 21,
            letterSpacing: -0.31,
        )
        /// Figma `iOS/Subheadline`.
        public static let subheadline = TypeStyle(
            "iOS/Subheadline",
            textStyle: .subheadline,
            weight: .regular,
            size: 15,
            lineHeight: 20,
            letterSpacing: -0.23,
        )
        /// Figma `iOS/Footnote`.
        public static let footnote = TypeStyle(
            "iOS/Footnote",
            textStyle: .footnote,
            weight: .regular,
            size: 13,
            lineHeight: 18,
            letterSpacing: -0.08,
        )
        /// Figma `iOS/Caption 1`.
        public static let caption1 = TypeStyle(
            "iOS/Caption 1",
            textStyle: .caption1,
            weight: .regular,
            size: 12,
            lineHeight: 16,
            letterSpacing: 0,
        )
        /// Figma `iOS/Caption 2`.
        public static let caption2 = TypeStyle(
            "iOS/Caption 2",
            textStyle: .caption2,
            weight: .regular,
            size: 11,
            lineHeight: 13,
            letterSpacing: 0.06,
        )
        /// Figma `iOS/Body Emphasized`.
        public static let bodyEmphasized = TypeStyle(
            "iOS/Body Emphasized",
            textStyle: .body,
            weight: .semibold,
            size: 17,
            lineHeight: 22,
            letterSpacing: -0.43,
        )
        /// Figma `iOS/Subheadline Emphasized`.
        public static let subheadlineEmphasized = TypeStyle(
            "iOS/Subheadline Emphasized",
            textStyle: .subheadline,
            weight: .semibold,
            size: 15,
            lineHeight: 20,
            letterSpacing: -0.23,
        )
        /// Figma `iOS/Footnote Emphasized`.
        public static let footnoteEmphasized = TypeStyle(
            "iOS/Footnote Emphasized",
            textStyle: .footnote,
            weight: .semibold,
            size: 13,
            lineHeight: 18,
            letterSpacing: -0.08,
        )

        /// Every style in this group, in Figma order.
        public static let all: [TypeStyle] = [
            largeTitle,
            title1,
            title2,
            title3,
            headline,
            body,
            callout,
            subheadline,
            footnote,
            caption1,
            caption2,
            bodyEmphasized,
            subheadlineEmphasized,
            footnoteEmphasized,
        ]
    }
}

extension Typography {
    /// macOS (SF Pro).
    public enum MacOS {
        /// Figma `macOS/Large Title`.
        public static let largeTitle = TypeStyle(
            "macOS/Large Title",
            textStyle: .largeTitle,
            weight: .regular,
            size: 26,
            lineHeight: 32,
            letterSpacing: 0.22,
        )
        /// Figma `macOS/Title 1`.
        public static let title1 = TypeStyle(
            "macOS/Title 1",
            textStyle: .title1,
            weight: .regular,
            size: 22,
            lineHeight: 26,
            letterSpacing: -0.26,
        )
        /// Figma `macOS/Title 2`.
        public static let title2 = TypeStyle(
            "macOS/Title 2",
            textStyle: .title2,
            weight: .regular,
            size: 17,
            lineHeight: 22,
            letterSpacing: -0.43,
        )
        /// Figma `macOS/Title 3`.
        public static let title3 = TypeStyle(
            "macOS/Title 3",
            textStyle: .title3,
            weight: .regular,
            size: 15,
            lineHeight: 20,
            letterSpacing: -0.23,
        )
        /// Figma `macOS/Headline`.
        public static let headline = TypeStyle(
            "macOS/Headline",
            textStyle: .headline,
            weight: .bold,
            size: 13,
            lineHeight: 16,
            letterSpacing: -0.08,
        )
        /// Figma `macOS/Body`.
        public static let body = TypeStyle(
            "macOS/Body",
            textStyle: .body,
            weight: .regular,
            size: 13,
            lineHeight: 16,
            letterSpacing: -0.08,
        )
        /// Figma `macOS/Callout`.
        public static let callout = TypeStyle(
            "macOS/Callout",
            textStyle: .callout,
            weight: .regular,
            size: 12,
            lineHeight: 15,
            letterSpacing: 0,
        )
        /// Figma `macOS/Subheadline`.
        public static let subheadline = TypeStyle(
            "macOS/Subheadline",
            textStyle: .subheadline,
            weight: .regular,
            size: 11,
            lineHeight: 14,
            letterSpacing: 0.06,
        )
        /// Figma `macOS/Footnote`.
        public static let footnote = TypeStyle(
            "macOS/Footnote",
            textStyle: .footnote,
            weight: .regular,
            size: 10,
            lineHeight: 13,
            letterSpacing: 0.12,
        )
        /// Figma `macOS/Caption 1`.
        public static let caption1 = TypeStyle(
            "macOS/Caption 1",
            textStyle: .caption1,
            weight: .regular,
            size: 10,
            lineHeight: 13,
            letterSpacing: 0.12,
        )
        /// Figma `macOS/Caption 2`.
        public static let caption2 = TypeStyle(
            "macOS/Caption 2",
            textStyle: .caption2,
            weight: .medium,
            size: 10,
            lineHeight: 13,
            letterSpacing: 0.12,
        )
        /// Figma `macOS/Body Emphasized`.
        public static let bodyEmphasized = TypeStyle(
            "macOS/Body Emphasized",
            textStyle: .body,
            weight: .semibold,
            size: 13,
            lineHeight: 16,
            letterSpacing: -0.08,
        )

        /// Every style in this group, in Figma order.
        public static let all: [TypeStyle] = [
            largeTitle,
            title1,
            title2,
            title3,
            headline,
            body,
            callout,
            subheadline,
            footnote,
            caption1,
            caption2,
            bodyEmphasized,
        ]
    }
}

extension Typography {
    /// watchOS (SF Compact), default size.
    public enum WatchOS {
        /// Figma `watchOS/Large Title`.
        public static let largeTitle = TypeStyle(
            "watchOS/Large Title",
            textStyle: .largeTitle,
            weight: .regular,
            size: 36,
            lineHeight: 41,
            letterSpacing: 0,
        )
        /// Figma `watchOS/Title 1`.
        public static let title1 = TypeStyle(
            "watchOS/Title 1",
            textStyle: .title1,
            weight: .regular,
            size: 30,
            lineHeight: 32,
            letterSpacing: 0,
        )
        /// Figma `watchOS/Title 2`.
        public static let title2 = TypeStyle(
            "watchOS/Title 2",
            textStyle: .title2,
            weight: .regular,
            size: 24,
            lineHeight: 26,
            letterSpacing: 0,
        )
        /// Figma `watchOS/Title 3`.
        public static let title3 = TypeStyle(
            "watchOS/Title 3",
            textStyle: .title3,
            weight: .regular,
            size: 19,
            lineHeight: 21,
            letterSpacing: 0,
        )
        /// Figma `watchOS/Headline`.
        public static let headline = TypeStyle(
            "watchOS/Headline",
            textStyle: .headline,
            weight: .semibold,
            size: 16,
            lineHeight: 19,
            letterSpacing: 0,
        )
        /// Figma `watchOS/Body`.
        public static let body = TypeStyle(
            "watchOS/Body",
            textStyle: .body,
            weight: .regular,
            size: 16,
            lineHeight: 19,
            letterSpacing: 0,
        )
        /// Figma `watchOS/Caption 1`.
        public static let caption1 = TypeStyle(
            "watchOS/Caption 1",
            textStyle: .caption1,
            weight: .regular,
            size: 15,
            lineHeight: 18,
            letterSpacing: 0,
        )
        /// Figma `watchOS/Caption 2`.
        public static let caption2 = TypeStyle(
            "watchOS/Caption 2",
            textStyle: .caption2,
            weight: .regular,
            size: 14,
            lineHeight: 17,
            letterSpacing: 0,
        )
        /// Figma `watchOS/Footnote`.
        public static let footnote = TypeStyle(
            "watchOS/Footnote",
            textStyle: .footnote,
            weight: .regular,
            size: 13,
            lineHeight: 16,
            letterSpacing: 0,
        )

        /// Every style in this group, in Figma order.
        public static let all: [TypeStyle] = [
            largeTitle,
            title1,
            title2,
            title3,
            headline,
            body,
            caption1,
            caption2,
            footnote,
        ]
    }
}

extension Typography {
    /// Money amounts: Rounded design with monospaced digits on every platform.
    public enum Amount {
        /// Figma `Amount/iOS Hero`.
        public static let iOSHero = TypeStyle(
            "Amount/iOS Hero",
            textStyle: .largeTitle,
            weight: .semibold,
            size: 34,
            lineHeight: 41,
            letterSpacing: 0.4,
            design: .rounded,
            monospacedDigits: true,
        )
        /// Figma `Amount/iOS Title`.
        public static let iOSTitle = TypeStyle(
            "Amount/iOS Title",
            textStyle: .title2,
            weight: .semibold,
            size: 22,
            lineHeight: 28,
            letterSpacing: -0.26,
            design: .rounded,
            monospacedDigits: true,
        )
        /// Figma `Amount/iOS Body`.
        public static let iOSBody = TypeStyle(
            "Amount/iOS Body",
            textStyle: .body,
            weight: .medium,
            size: 17,
            lineHeight: 22,
            letterSpacing: -0.43,
            design: .rounded,
            monospacedDigits: true,
        )
        /// Figma `Amount/iOS Small`.
        public static let iOSSmall = TypeStyle(
            "Amount/iOS Small",
            textStyle: .subheadline,
            weight: .medium,
            size: 15,
            lineHeight: 20,
            letterSpacing: -0.23,
            design: .rounded,
            monospacedDigits: true,
        )
        /// Figma `Amount/macOS Title`.
        public static let macOSTitle = TypeStyle(
            "Amount/macOS Title",
            textStyle: .title1,
            weight: .semibold,
            size: 22,
            lineHeight: 26,
            letterSpacing: -0.26,
            design: .rounded,
            monospacedDigits: true,
        )
        /// Figma `Amount/macOS Body`.
        public static let macOSBody = TypeStyle(
            "Amount/macOS Body",
            textStyle: .body,
            weight: .medium,
            size: 13,
            lineHeight: 16,
            letterSpacing: -0.08,
            design: .rounded,
            monospacedDigits: true,
        )
        /// Figma `Amount/watchOS Hero`.
        public static let watchOSHero = TypeStyle(
            "Amount/watchOS Hero",
            textStyle: .title1,
            weight: .semibold,
            size: 30,
            lineHeight: 32,
            letterSpacing: 0,
            design: .rounded,
            monospacedDigits: true,
        )
        /// Figma `Amount/watchOS Body`.
        public static let watchOSBody = TypeStyle(
            "Amount/watchOS Body",
            textStyle: .body,
            weight: .medium,
            size: 16,
            lineHeight: 19,
            letterSpacing: 0,
            design: .rounded,
            monospacedDigits: true,
        )

        /// Every style in this group, in Figma order.
        public static let all: [TypeStyle] = [
            iOSHero,
            iOSTitle,
            iOSBody,
            iOSSmall,
            macOSTitle,
            macOSBody,
            watchOSHero,
            watchOSBody,
        ]
    }
}

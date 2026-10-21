#if canImport(SwiftUI)
    import SwiftUI

    extension Font {
        /// The system font for a design-system text style. It uses Apple's text style, so it
        /// scales with Dynamic Type, plus the token's weight, design and digit spacing.
        public static func theme(_ style: TypeStyle) -> Font {
            let font = Font.system(style.textStyle.fontTextStyle, design: style.design.fontDesign)
                .weight(style.weight.fontWeight)
            return style.monospacedDigits ? font.monospacedDigit() : font
        }
    }

    extension TypeStyle.TextStyle {
        var fontTextStyle: Font.TextStyle {
            switch self {
            case .largeTitle: .largeTitle
            case .title1: .title
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .body: .body
            case .callout: .callout
            case .subheadline: .subheadline
            case .footnote: .footnote
            case .caption1: .caption
            case .caption2: .caption2
            }
        }
    }

    extension TypeStyle.Weight {
        var fontWeight: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }
    }

    extension TypeStyle.Design {
        var fontDesign: Font.Design {
            switch self {
            case .standard: .default
            case .rounded: .rounded
            }
        }
    }

    extension Typography {
        /// Text styles for the platform this code runs on, followed by its amount styles.
        public static var currentPlatform: [TypeStyle] {
            #if os(macOS)
                return MacOS.all + [Amount.macOSTitle, Amount.macOSBody]
            #elseif os(watchOS)
                return WatchOS.all + [Amount.watchOSHero, Amount.watchOSBody]
            #else
                return IOS.all + [Amount.iOSHero, Amount.iOSTitle, Amount.iOSBody, Amount.iOSSmall]
            #endif
        }
    }
#endif

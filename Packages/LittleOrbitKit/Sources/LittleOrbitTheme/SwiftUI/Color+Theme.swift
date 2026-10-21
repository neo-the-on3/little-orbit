#if canImport(SwiftUI)
    import SwiftUI
    #if canImport(UIKit)
        import UIKit
    #elseif canImport(AppKit)
        import AppKit
    #endif

    extension RGBAColor {
        /// This colour as a SwiftUI `Color` in the sRGB colour space.
        public var color: Color {
            Color(
                .sRGB,
                red: Double(red) / 255,
                green: Double(green) / 255,
                blue: Double(blue) / 255,
                opacity: Double(alpha) / 255,
            )
        }
    }

    extension Color {
        /// A colour that follows the current appearance: the token's Light value in light mode
        /// and its Dark value in dark mode. watchOS is always dark, so it uses the Dark value.
        public init(_ token: ColorToken) {
            #if os(watchOS)
                self = token.dark.color
            #elseif canImport(UIKit)
                self.init(
                    uiColor: UIColor { traits in
                        traits.userInterfaceStyle == .dark ? UIColor(token.dark) : UIColor(token.light)
                    }
                )
            #elseif canImport(AppKit)
                self.init(
                    nsColor: NSColor(name: nil) { appearance in
                        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                        return isDark ? NSColor(token.dark) : NSColor(token.light)
                    }
                )
            #else
                self = token.light.color
            #endif
        }
    }

    #if canImport(UIKit) && !os(watchOS)
        extension UIColor {
            fileprivate convenience init(_ color: RGBAColor) {
                self.init(
                    red: CGFloat(color.red) / 255,
                    green: CGFloat(color.green) / 255,
                    blue: CGFloat(color.blue) / 255,
                    alpha: CGFloat(color.alpha) / 255,
                )
            }
        }
    #elseif canImport(AppKit)
        extension NSColor {
            fileprivate convenience init(_ color: RGBAColor) {
                self.init(
                    srgbRed: CGFloat(color.red) / 255,
                    green: CGFloat(color.green) / 255,
                    blue: CGFloat(color.blue) / 255,
                    alpha: CGFloat(color.alpha) / 255,
                )
            }
        }
    #endif
#endif

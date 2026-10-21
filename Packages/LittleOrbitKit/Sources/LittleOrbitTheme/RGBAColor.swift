import Foundation

/// An sRGB colour with 8-bit channels, written the way Figma reports it.
public struct RGBAColor: Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA`, in either case, as Figma prints it.
    /// Returns `nil` for anything else.
    public init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let digits = Array(hex.dropFirst())
        guard digits.count == 6 || digits.count == 8 else { return nil }
        var channels: [UInt8] = []
        var index = 0
        while index < digits.count {
            guard let value = UInt8(String(digits[index..<index + 2]), radix: 16) else { return nil }
            channels.append(value)
            index += 2
        }
        self.init(
            red: channels[0],
            green: channels[1],
            blue: channels[2],
            alpha: channels.count == 4 ? channels[3] : 255,
        )
    }

    /// Lowercase `#rrggbb`, or `#rrggbbaa` when the colour is not opaque.
    public var hexString: String {
        let channels = alpha == 255 ? [red, green, blue] : [red, green, blue, alpha]
        return "#" + channels.map { Self.twoDigitHex($0) }.joined()
    }

    /// WCAG 2.x relative luminance of the colour, ignoring alpha.
    public var relativeLuminance: Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            if value <= 0.040_45 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2.x contrast ratio between two opaque colours, from 1 to 21.
    public func contrastRatio(with other: RGBAColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func twoDigitHex(_ value: UInt8) -> String {
        let digits = String(value, radix: 16)
        return digits.count == 1 ? "0" + digits : digits
    }
}

extension RGBAColor: ExpressibleByStringLiteral {
    /// Token tables are written with Figma's hex strings. A malformed literal is a
    /// programming error, so it traps at first use and in the token tests.
    public init(stringLiteral value: String) {
        guard let color = RGBAColor(hex: value) else {
            preconditionFailure("Invalid hex colour literal \(value)")
        }
        self = color
    }
}

/// A semantic colour with its Light and Dark mode values.
public struct ColorToken: Hashable, Sendable {
    /// The Figma variable name, such as `bg/primary`.
    public let figmaName: String
    public let light: RGBAColor
    public let dark: RGBAColor

    public init(_ figmaName: String, light: RGBAColor, dark: RGBAColor) {
        self.figmaName = figmaName
        self.light = light
        self.dark = dark
    }
}

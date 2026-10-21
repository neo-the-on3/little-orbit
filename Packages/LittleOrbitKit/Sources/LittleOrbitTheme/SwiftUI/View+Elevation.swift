#if canImport(SwiftUI)
    import SwiftUI

    extension View {
        /// Applies an elevation's shadows in light mode. Dark mode draws no shadow; put the
        /// surface on `ThemeColor.bgElevated` instead, as the design system specifies.
        public func themeElevation(_ token: ElevationToken) -> some View {
            modifier(ElevationModifier(token: token))
        }
    }

    private struct ElevationModifier: ViewModifier {
        let token: ElevationToken
        @Environment(\.colorScheme) private var colorScheme

        func body(content: Content) -> some View {
            // Elevation tokens have at most two layers (checked by the token tests).
            let layers = colorScheme == .dark ? [] : token.layers
            return
                content
                .themeShadow(layers.first)
                .themeShadow(layers.dropFirst().first)
        }
    }

    extension View {
        /// Figma's blur radius is about twice SwiftUI's shadow radius, so it is halved here.
        fileprivate func themeShadow(_ layer: ShadowLayer?) -> some View {
            shadow(
                color: layer?.color.color ?? .clear,
                radius: (layer?.blur ?? 0) / 2,
                x: layer?.offsetX ?? 0,
                y: layer?.offsetY ?? 0,
            )
        }
    }
#endif

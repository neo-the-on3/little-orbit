#if canImport(SwiftUI)
    import SwiftUI

    /// A sample screen that shows every design token in the current appearance and Dynamic
    /// Type size. Use it in previews to compare the theme with the Figma design system.
    public struct ThemeSwatchView: View {
        public init() {}

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.space6) {
                    section("Semantic colours") {
                        ForEach(ThemeColor.all, id: \.figmaName) { token in
                            colorRow(token)
                        }
                    }
                    section("Category hues") {
                        ForEach(CategoryColor.all, id: \.figmaName) { token in
                            colorRow(token)
                        }
                    }
                    section("Typography") {
                        ForEach(Typography.currentPlatform, id: \.figmaName) { style in
                            typeSample(style)
                        }
                    }
                    section("Spacing") {
                        ForEach(Spacing.all, id: \.figmaName) { step in
                            measureRow(step.figmaName, value: step.value) {
                                Rectangle()
                                    .fill(Color(ThemeColor.accentDefault))
                                    .frame(width: step.value, height: Spacing.space3)
                            }
                        }
                    }
                    section("Radius") {
                        ForEach(Radius.all, id: \.figmaName) { radius in
                            measureRow(radius.figmaName, value: radius.value) {
                                RoundedRectangle(cornerRadius: radius.value, style: .continuous)
                                    .fill(Color(ThemeColor.accentTint))
                                    .frame(width: Spacing.space12, height: Spacing.space12)
                            }
                        }
                    }
                    section("Elevation") {
                        ForEach(Elevation.all, id: \.figmaName) { level in
                            Text(level.figmaName)
                                .font(.footnote)
                                .foregroundStyle(Color(ThemeColor.labelPrimary))
                                .padding(Spacing.space4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    Color(ThemeColor.bgElevated),
                                    in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous),
                                )
                                .themeElevation(level)
                        }
                    }
                }
                .padding(Spacing.space4)
            }
            .background(Color(ThemeColor.bgGrouped))
        }

        private func section<Content: View>(
            _ title: String,
            @ViewBuilder content: () -> Content,
        ) -> some View {
            VStack(alignment: .leading, spacing: Spacing.space2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color(ThemeColor.labelPrimary))
                content()
            }
        }

        private func colorRow(_ token: ColorToken) -> some View {
            HStack(spacing: Spacing.space3) {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Color(token))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(Color(ThemeColor.separatorDefault))
                    }
                    .frame(width: Spacing.space8, height: Spacing.space8)
                VStack(alignment: .leading) {
                    Text(token.figmaName)
                        .font(.footnote)
                        .foregroundStyle(Color(ThemeColor.labelPrimary))
                    Text("\(token.light.hexString) · \(token.dark.hexString)")
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                }
            }
        }

        /// Amount styles also show a sample figure, so the rounded, even-width digits are visible.
        private func typeSample(_ style: TypeStyle) -> some View {
            VStack(alignment: .leading, spacing: Spacing.space1) {
                Text(style.figmaName)
                    .font(.theme(style))
                    .foregroundStyle(Color(ThemeColor.labelPrimary))
                if style.monospacedDigits {
                    Text(Self.amountSample)
                        .font(.theme(style))
                        .foregroundStyle(Color(ThemeColor.labelPrimary))
                }
            }
        }

        private static let amountSample = "1,234,567.89"

        private func measureRow<Sample: View>(
            _ name: String,
            value: Double,
            @ViewBuilder sample: () -> Sample,
        ) -> some View {
            HStack(spacing: Spacing.space3) {
                Text("\(name) · \(value.formatted()) pt")
                    .font(.footnote)
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                Spacer(minLength: Spacing.space2)
                sample()
            }
        }
    }

    #Preview("Light") {
        ThemeSwatchView()
            .preferredColorScheme(.light)
    }

    #Preview("Dark") {
        ThemeSwatchView()
            .preferredColorScheme(.dark)
    }

    #Preview("Accessibility 3") {
        ThemeSwatchView()
            .dynamicTypeSize(.accessibility3)
    }
#endif

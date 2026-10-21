import LittleOrbitCore
import LittleOrbitDomain
import LittleOrbitPersistence
import LittleOrbitTheme
import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: Spacing.space3) {
            Text(LittleOrbitCore.placeholderTitle)
                .font(.theme(Self.titleStyle))
                .foregroundStyle(Color(ThemeColor.labelPrimary))
            Text("Placeholder")
                .foregroundStyle(Color(ThemeColor.labelSecondary))
            Text(linkedModules)
                .font(.theme(Self.footnoteStyle))
                .foregroundStyle(Color(ThemeColor.labelTertiary))
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(ThemeColor.bgPrimary))
    }

    // Each platform uses its own Title 2 and Footnote styles from the design system.
    #if os(macOS)
        private static let titleStyle = Typography.MacOS.title2
        private static let footnoteStyle = Typography.MacOS.footnote
    #elseif os(watchOS)
        private static let titleStyle = Typography.WatchOS.title2
        private static let footnoteStyle = Typography.WatchOS.footnote
    #else
        private static let titleStyle = Typography.IOS.title2
        private static let footnoteStyle = Typography.IOS.footnote
    #endif

    private var linkedModules: String {
        [
            LittleOrbitCore.moduleName,
            LittleOrbitDomain.moduleName,
            LittleOrbitPersistence.moduleName,
            LittleOrbitTheme.moduleName,
        ]
        .joined(separator: "\n")
    }
}

#Preview {
    RootView()
}

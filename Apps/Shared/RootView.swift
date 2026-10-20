import LittleOrbitCore
import LittleOrbitDomain
import LittleOrbitPersistence
import LittleOrbitTheme
import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text(LittleOrbitCore.placeholderTitle)
                .font(.title2)
            Text("Placeholder")
                .foregroundStyle(.secondary)
            Text(linkedModules)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

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

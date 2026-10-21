/// Screens of the app, one folder per feature.
///
/// Each feature has `@Observable`, `@MainActor` view models that depend only on use-case protocols from
/// `LittleOrbitDomain`, injected through their initializers. This module never imports `LittleOrbitPersistence`:
/// the App target is the composition root that opens the store and wires the implementations in.
/// View models build on Linux and are tested there.
/// SwiftUI views sit in each feature's `Views` folder behind `#if canImport(SwiftUI)`.
public enum LittleOrbitFeatures {
    public static let moduleName = "LittleOrbitFeatures"
}

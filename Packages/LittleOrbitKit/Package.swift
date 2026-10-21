// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "LittleOrbitKit",
    platforms: [
        .iOS(.v27),
        .macOS(.v27),
        .watchOS(.v27),
    ],
    products: [
        .library(name: "LittleOrbitCore", targets: ["LittleOrbitCore"]),
        .library(name: "LittleOrbitDomain", targets: ["LittleOrbitDomain"]),
        .library(name: "LittleOrbitPersistence", targets: ["LittleOrbitPersistence"]),
        .library(name: "LittleOrbitTheme", targets: ["LittleOrbitTheme"]),
    ],
    targets: [
        .target(name: "LittleOrbitCore"),
        .target(
            name: "LittleOrbitDomain",
            dependencies: ["LittleOrbitCore"],
        ),
        .target(
            name: "LittleOrbitPersistence",
            dependencies: ["LittleOrbitDomain"],
        ),
        .target(
            name: "LittleOrbitTheme",
            dependencies: ["LittleOrbitCore"],
        ),
        .testTarget(
            name: "LittleOrbitCoreTests",
            dependencies: ["LittleOrbitCore"],
        ),
        .testTarget(
            name: "LittleOrbitDomainTests",
            dependencies: ["LittleOrbitDomain"],
        ),
        .testTarget(
            name: "LittleOrbitPersistenceTests",
            dependencies: ["LittleOrbitPersistence"],
        ),
        .testTarget(
            name: "LittleOrbitThemeTests",
            dependencies: ["LittleOrbitTheme"],
            resources: [.copy("Fixtures")],
        ),
    ],
)

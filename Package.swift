// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FinderCut",
    defaultLocalization: "fr",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "FinderCut", targets: ["FinderCut"]),
        .library(name: "FinderCutCore", targets: ["FinderCutCore"]),
    ],
    targets: [
        .target(
            name: "FinderCutCore",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "FinderCut",
            dependencies: ["FinderCutCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "FinderCutCoreTests",
            dependencies: ["FinderCutCore"]
        ),
    ]
)

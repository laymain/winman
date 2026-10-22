// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WinMan",
    platforms: [.macOS(.v14)],
    products: [
        // Pure window-state logic. Buildable and testable with only the
        // Command Line Tools.
        .library(name: "WinManCore", targets: ["WinManCore"]),
        // The menu-bar application. Requires the full Xcode toolchain to build
        // (SwiftUI macros are not present in the CLT toolchain).
        .executable(name: "WinMan", targets: ["WinMan"])
    ],
    targets: [
        // Pure state machine + geometry. No SwiftUI, so it compiles anywhere.
        .target(
            name: "WinManCore",
            dependencies: [],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "WinMan",
            dependencies: ["WinManCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "WinManCoreTests",
            dependencies: ["WinManCore"]
        )
    ]
)

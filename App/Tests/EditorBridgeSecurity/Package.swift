// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "EditorBridgeSecurity",
    targets: [
        .target(
            name: "UniformTypeIdentifiers",
            path: "Stubs/UniformTypeIdentifiers"
        ),
        .target(
            name: "AppKit",
            dependencies: ["UniformTypeIdentifiers"],
            path: "Stubs/AppKit"
        ),
        .target(
            name: "WebKit",
            dependencies: ["AppKit"],
            path: "Stubs/WebKit"
        ),
        .target(
            name: "MacDrawApp",
            dependencies: ["AppKit", "WebKit", "UniformTypeIdentifiers"],
            path: "MacDrawSources"
        ),
        .testTarget(
            name: "EditorBridgeSecurityTests",
            dependencies: ["MacDrawApp", "WebKit", "AppKit"],
            path: "Tests"
        ),
    ]
)

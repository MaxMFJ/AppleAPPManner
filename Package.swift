// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PixelWorkspace",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PixelWorkspace", targets: ["PixelWorkspace"])],
    targets: [
        .executableTarget(name: "PixelWorkspace", path: "Sources/PixelWorkspace"),
        .testTarget(name: "PixelWorkspaceTests", dependencies: ["PixelWorkspace"], path: "Tests/PixelWorkspaceTests")
    ]
)

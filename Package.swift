// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClearDisk",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .executable(name: "scan-cli", targets: ["scan-cli"]),
        .executable(name: "ClearDiskApp", targets: ["ClearDiskApp"]),
    ],
    targets: [
        .target(name: "Core"),
        .executableTarget(name: "scan-cli", dependencies: ["Core"]),
        // Local dev shell; the signed/sandboxed Xcode app targets come at
        // distribution time (needs Apple Developer account).
        .executableTarget(name: "ClearDiskApp", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)

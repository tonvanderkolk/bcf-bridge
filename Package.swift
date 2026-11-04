// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BCFBridge",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "BridgeCore", path: "Sources/BridgeCore"),
        .executableTarget(
            name: "bcf-bridge",
            dependencies: ["BridgeCore"],
            path: "Sources/bcf-bridge",
            linkerSettings: [.linkedFramework("CoreMIDI")]
        ),
    ]
)

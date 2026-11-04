// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BCFBridge",
    platforms: [.macOS(.v13)],
    targets: [
        // Vertaallogica zonder hardware
        .target(name: "BridgeCore", path: "Sources/BridgeCore"),
        // CoreMIDI, log en de motor die alles verbindt (gedeeld door CLI en app)
        .target(
            name: "BridgeEngine",
            dependencies: ["BridgeCore"],
            path: "Sources/BridgeEngine",
            linkerSettings: [.linkedFramework("CoreMIDI")]
        ),
        .executableTarget(
            name: "bcf-bridge",
            dependencies: ["BridgeCore", "BridgeEngine"],
            path: "Sources/bcf-bridge"
        ),
        .executableTarget(
            name: "BCFBridgeApp",
            dependencies: ["BridgeCore", "BridgeEngine"],
            path: "Sources/BCFBridgeApp",
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
    ]
)

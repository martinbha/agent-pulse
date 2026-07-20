// swift-tools-version: 6.0

import PackageDescription

let swift5Mode: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "agent-pulse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "agent-pulse", targets: ["AgentPulse"]),
        .executable(name: "agent-pulse-notifier", targets: ["AgentPulseNotifier"])
    ],
    targets: [
        .target(
            name: "AgentPulseBridgeSupport",
            path: "Sources/AgentPulseBridgeSupport",
            swiftSettings: swift5Mode
        ),
        .target(
            name: "AgentPulseCore",
            path: "Sources/AgentPulseCore",
            exclude: ["Resources"],
            swiftSettings: swift5Mode
        ),
        .executableTarget(
            name: "AgentPulse",
            dependencies: ["AgentPulseCore"],
            path: "Sources/AgentPulse",
            swiftSettings: swift5Mode
        ),
        .executableTarget(
            name: "AgentPulseNotifier",
            dependencies: ["AgentPulseCore"],
            path: "Sources/AgentPulseNotifier",
            swiftSettings: swift5Mode
        ),
        .testTarget(
            name: "AgentPulseCoreTests",
            dependencies: ["AgentPulseCore"],
            path: "Tests/AgentPulseCoreTests",
            swiftSettings: swift5Mode
        ),
        .testTarget(
            name: "AgentPulseBridgeSupportTests",
            dependencies: ["AgentPulseBridgeSupport"],
            path: "Tests/AgentPulseBridgeSupportTests",
            swiftSettings: swift5Mode
        )
    ]
)

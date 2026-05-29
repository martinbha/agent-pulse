// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "agent-pulse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "agent-pulse", targets: ["AgentPulse"])
    ],
    targets: [
        .executableTarget(
            name: "AgentPulse",
            path: "Sources/AgentPulse",
            exclude: ["Resources"]
        )
    ]
)

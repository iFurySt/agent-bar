// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "agent-bar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "AgentBar", targets: ["AgentBar"]),
    ],
    targets: [
        .target(
            name: "AgentBarCore"),
        .executableTarget(
            name: "AgentBar",
            dependencies: ["AgentBarCore"],
            resources: [
                .process("Resources"),
            ]),
        .testTarget(
            name: "AgentBarCoreTests",
            dependencies: ["AgentBarCore"]),
    ])

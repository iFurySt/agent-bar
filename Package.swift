// swift-tools-version: 6.2
import PackageDescription

#if os(macOS)
let products: [Product] = [
    .executable(name: "AgentBar", targets: ["AgentBar"]),
]
let targets: [Target] = [
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
]
#else
let products: [Product] = []
let targets: [Target] = [
    .target(
        name: "AgentBarCore"),
    .testTarget(
        name: "AgentBarCoreTests",
        dependencies: ["AgentBarCore"]),
]
#endif

let package = Package(
    name: "agent-bar",
    platforms: [
        .macOS(.v14),
    ],
    products: products,
    targets: targets)

// swift-tools-version: 6.2
import PackageDescription

#if os(macOS)
let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.1"),
]
let products: [Product] = [
    .executable(name: "AgentBar", targets: ["AgentBar"]),
]
let targets: [Target] = [
    .target(
        name: "AgentBarCore"),
    .executableTarget(
        name: "AgentBar",
        dependencies: [
            "AgentBarCore",
            .product(name: "Sparkle", package: "Sparkle"),
        ],
        resources: [
            .process("Resources"),
        ]),
    .testTarget(
        name: "AgentBarCoreTests",
        dependencies: ["AgentBarCore"]),
]
#else
let dependencies: [Package.Dependency] = []
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
    dependencies: dependencies,
    targets: targets)

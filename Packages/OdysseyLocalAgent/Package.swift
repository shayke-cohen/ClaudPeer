// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OdysseyLocalAgent",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "OdysseyLocalAgentCore",
            targets: ["OdysseyLocalAgentCore"]
        ),
        .executable(
            name: "OdysseyLocalAgentHost",
            targets: ["OdysseyLocalAgentHost"]
        ),
    ],
    targets: [
        .target(
            name: "OdysseyLocalAgentCore",
            path: "Sources/OdysseyLocalAgentCore"
        ),
        .executableTarget(
            name: "OdysseyLocalAgentHost",
            dependencies: ["OdysseyLocalAgentCore"],
            path: "Sources/OdysseyLocalAgentHost"
        ),
        .testTarget(
            name: "OdysseyLocalAgentCoreTests",
            dependencies: ["OdysseyLocalAgentCore"],
            path: "Tests/OdysseyLocalAgentCoreTests"
        ),
    ]
)

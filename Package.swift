// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HermesConfigGuardian",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GuardianCore", targets: ["GuardianCore"]),
        .executable(name: "HermesConfigGuardian", targets: ["HermesConfigGuardian"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
    ],
    targets: [
        .target(
            name: "GuardianCore",
            dependencies: ["Yams"]
        ),
        .executableTarget(
            name: "HermesConfigGuardian",
            dependencies: ["GuardianCore"]
        ),
        .testTarget(
            name: "GuardianCoreTests",
            dependencies: ["GuardianCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)

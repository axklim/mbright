// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mbright",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mbright", targets: ["mbright"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2")
    ],
    targets: [
        .target(name: "MBrightCore"),
        .executableTarget(
            name: "mbright",
            dependencies: [
                "MBrightCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "MBrightCoreTests", dependencies: ["MBrightCore"]),
    ]
)

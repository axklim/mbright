// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mbright",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mbright", targets: ["mbright"]),
        .executable(name: "mbrightd", targets: ["mbrightd"]),
        .executable(name: "mbright-menubar", targets: ["mbright-menubar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2")
    ],
    targets: [
        .target(name: "MBrightCore"),
        .target(name: "MBrightIPC", dependencies: ["MBrightCore"]),
        .target(name: "MBrightMenuBar", dependencies: ["MBrightCore", "MBrightIPC"]),
        .executableTarget(
            name: "mbright",
            dependencies: [
                "MBrightCore",
                "MBrightIPC",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "mbrightd",
            dependencies: [
                "MBrightCore",
                "MBrightIPC",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "mbright-menubar",
            dependencies: ["MBrightCore", "MBrightIPC", "MBrightMenuBar"]
        ),
        .testTarget(name: "MBrightCoreTests", dependencies: ["MBrightCore"]),
        .testTarget(name: "MBrightIPCTests", dependencies: ["MBrightCore", "MBrightIPC"]),
        .testTarget(name: "MBrightMenuBarTests", dependencies: ["MBrightCore", "MBrightIPC", "MBrightMenuBar"]),
    ]
)

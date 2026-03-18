// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "GannMT5Pro",
    platforms: [
        .iOS(.v15)   // Compatible con iOS 15.0+ (incluye 15.8.2)
    ],
    products: [
        .executable(name: "GannMT5Pro", targets: ["GannMT5Pro"]),
    ],
    targets: [
        .executableTarget(
            name: "GannMT5Pro",
            path: "Sources/GannMT5Pro",
            resources: [.process("../../Resources")]
        ),
    ]
)

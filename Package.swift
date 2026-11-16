// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HooenasNotchesSDK",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HooenasNotches", targets: ["HooenasNotches"]),
        .library(name: "HooenasNotchesProtocol", targets: ["HooenasNotchesProtocol"]),
        .executable(name: "hooenas-notches-host", targets: ["HooenasNotchesHost"]),
        .executable(name: "HooenasNotchesShowcase", targets: ["HooenasNotchesShowcase"]),
    ],
    targets: [
        .target(name: "HooenasNotches"),
        .target(name: "HooenasNotchesProtocol"),
        .executableTarget(name: "HooenasNotchesHost", dependencies: ["HooenasNotches", "HooenasNotchesProtocol"]),
        .executableTarget(name: "HooenasNotchesShowcase", dependencies: ["HooenasNotches"]),
        .testTarget(name: "HooenasNotchesTests", dependencies: ["HooenasNotches"]),
        .testTarget(name: "HooenasNotchesProtocolTests", dependencies: ["HooenasNotchesProtocol"]),
    ]
)

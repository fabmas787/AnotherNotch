// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NotchKit", targets: ["NotchKit"]),
        .executable(name: "Notch", targets: ["Notch"]),
        .executable(name: "NotchTestRunner", targets: ["NotchTestRunner"]),
    ],
    targets: [
        .target(
            name: "NotchKit",
            path: "Sources/NotchKit"
        ),
        .executableTarget(
            name: "Notch",
            dependencies: ["NotchKit"],
            path: "Sources/NotchApp"
        ),
        .executableTarget(
            name: "NotchTestRunner",
            dependencies: ["NotchKit"],
            path: "Sources/NotchTestRunner"
        ),
    ]
)

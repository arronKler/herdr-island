// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HerdrIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HerdrIsland", targets: ["HerdrIsland"]),
        .library(name: "IslandCore", targets: ["IslandCore"]),
        .library(name: "HerdrKit", targets: ["HerdrKit"]),
    ],
    targets: [
        .target(name: "IslandCore", path: "Sources/IslandCore"),
        .target(name: "HerdrKit", dependencies: ["IslandCore"], path: "Sources/HerdrKit"),
        .executableTarget(
            name: "HerdrIsland",
            dependencies: ["IslandCore", "HerdrKit"],
            path: "Sources/IslandApp"
        ),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"], path: "Tests/IslandCoreTests"),
        .testTarget(
            name: "HerdrKitTests",
            dependencies: ["HerdrKit", "IslandCore"],
            path: "Tests/HerdrKitTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)

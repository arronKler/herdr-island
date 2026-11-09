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
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0"),
    ],
    targets: [
        .target(name: "IslandCore", path: "Sources/IslandCore"),
        .target(name: "HerdrKit", dependencies: ["IslandCore"], path: "Sources/HerdrKit"),
        .executableTarget(
            name: "HerdrIsland",
            dependencies: ["IslandCore", "HerdrKit", .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/IslandApp",
            resources: [.copy("Resources/Brand")]
        ),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"], path: "Tests/IslandCoreTests"),
        .testTarget(
            name: "HerdrKitTests",
            dependencies: ["HerdrKit", "IslandCore"],
            path: "Tests/HerdrKitTests"
        ),
        .testTarget(
            name: "IslandAppTests",
            dependencies: ["HerdrIsland", "HerdrKit", "IslandCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Tests/IslandAppTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)

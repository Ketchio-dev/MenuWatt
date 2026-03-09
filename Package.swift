// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MenuWatt",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MenuWatt", targets: ["MenuWatt"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4")
    ],
    targets: [
        .target(
            name: "MenuWattCore"
        ),
        .target(
            name: "MenuWattSystem",
            dependencies: ["MenuWattCore"]
        ),
        .executableTarget(
            name: "MenuWatt",
            dependencies: ["MenuWattCore", "MenuWattSystem"]
        ),
        .testTarget(
            name: "MenuWattTests",
            dependencies: [
                "MenuWatt",
                "MenuWattCore",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)

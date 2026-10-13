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
            name: "CIOReport"
        ),
        .target(
            name: "CMenuBar",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("Carbon")]
        ),
        .target(
            name: "MenuWattSystem",
            dependencies: ["MenuWattCore", "CIOReport"]
        ),
        .executableTarget(
            name: "MenuWatt",
            dependencies: ["MenuWattCore", "MenuWattSystem", "CMenuBar"]
        ),
        .testTarget(
            name: "MenuWattTests",
            dependencies: [
                "MenuWatt",
                "MenuWattCore",
                "MenuWattSystem",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/MenuWattTests"
        ),
    ]
)

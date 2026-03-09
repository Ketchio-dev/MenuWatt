// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Boochi",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Boochi", targets: ["Boochi"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4")
    ],
    targets: [
        .target(
            name: "BoochiCore",
            path: "Sources/BoochiCore"
        ),
        .target(
            name: "BoochiSystem",
            dependencies: ["BoochiCore"],
            path: "Sources/BoochiSystem"
        ),
        .executableTarget(
            name: "Boochi",
            dependencies: ["BoochiCore", "BoochiSystem"],
            path: "Sources/Boochi"
        ),
        .testTarget(
            name: "BoochiTests",
            dependencies: [
                "Boochi",
                "BoochiCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/BoochiTests"
        )
    ]
)

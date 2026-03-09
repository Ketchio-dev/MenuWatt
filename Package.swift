// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ChargeCat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ChargeCat", targets: ["ChargeCat"])
    ],
    targets: [
        .executableTarget(
            name: "ChargeCat",
            path: "Sources/ChargeCat"
        )
    ]
)

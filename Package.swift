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
    ]
)

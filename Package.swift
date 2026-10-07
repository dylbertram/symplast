// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MutagenDock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MutagenDock", targets: ["MutagenDock"])
    ],
    targets: [
        .executableTarget(
            name: "MutagenDock",
            path: "Sources/MutagenDock"
        ),
        .testTarget(name: "MutagenDockTests", dependencies: ["MutagenDock"])
    ]
)

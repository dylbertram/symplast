// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Symplast",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Symplast", targets: ["Symplast"])
    ],
    targets: [
        .executableTarget(
            name: "Symplast",
            path: "Sources/Symplast"
        ),
        .testTarget(name: "SymplastTests", dependencies: ["Symplast"])
    ]
)

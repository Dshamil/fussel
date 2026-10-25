// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Fussel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Fussel",
            path: "Sources/Fussel"
        ),
        .testTarget(
            name: "FusselTests",
            dependencies: ["Fussel"],
            path: "Tests/FusselTests"
        ),
    ]
)

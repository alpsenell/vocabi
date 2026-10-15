// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VocabCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VocabCore", targets: ["VocabCore"])
    ],
    targets: [
        .target(
            name: "VocabCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "VocabCoreTests",
            dependencies: ["VocabCore"]
        )
    ]
)
